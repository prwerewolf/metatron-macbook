"""Fast-mode boundaries use synthetic files, pipes and Unix socket pairs."""

import base64
import hashlib
import importlib.util
from pathlib import Path
import socket
import struct
import sys
import tarfile
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "daemon"))
import gguf_metadata as gguf
import nemotron_engine as fast

spec = importlib.util.spec_from_file_location("setup_fast", ROOT / "scripts/setup_fast.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def text(value):
    encoded = value.encode()
    return struct.pack("<Q", len(encoded)) + encoded


def model(path):
    entries = text("general.alignment") + struct.pack("<II", 4, 32)
    entries += text("asr.tokenizer.vocab") + struct.pack("<IIQ", 9, 8, 2) + text("▁test") + text("ing")
    tensor = text("synthetic") + struct.pack("<IQIQ", 1, 32, 0, 0)
    data = b"GGUF" + struct.pack("<IQQ", 3, 1, 2) + entries + tensor
    path.write_bytes(data + b"\0" * (-len(data) % 32) + bytes(range(128)))


class MetadataTests(unittest.TestCase):
    def test_repair_preserves_vocabulary_tensor_bytes_and_alignment(self):
        with tempfile.TemporaryDirectory() as temporary:
            original, repaired = Path(temporary) / "original", Path(temporary) / "repaired"
            model(original)
            tokenizer = b"synthetic tokenizer" * 100
            gguf.embed_tokenizer(original, repaired, tokenizer)
            before, after = gguf.read_metadata(original), gguf.read_metadata(repaired)
            self.assertEqual(after[0]["asr.tokenizer.vocab"], before[0]["asr.tokenizer.vocab"])
            self.assertEqual(gguf.embedded_tokenizer(repaired), tokenizer)
            self.assertEqual(repaired.read_bytes()[after[3]:], original.read_bytes()[before[3]:])
            self.assertEqual(after[3] % 32, 0)
            with self.assertRaisesRegex(ValueError, "already contains"):
                gguf.embed_tokenizer(repaired, Path(temporary) / "duplicate", tokenizer)

    def test_missing_tokenizer_cannot_silently_disable_boosting(self):
        with tempfile.TemporaryDirectory() as temporary:
            original = Path(temporary) / "model"
            model(original)
            with self.assertRaisesRegex(ValueError, "setup-fast"):
                gguf.embedded_tokenizer(original)

    def test_truncated_and_unbounded_headers_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "model"
            for data in (b"GGUF", b"GGUF" + struct.pack("<IQQ", 3, 1, 100000)):
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    gguf.read_metadata(path)

    def test_original_model_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            original = Path(temporary) / "model"
            model(original)
            before = original.read_bytes()
            with self.assertRaisesRegex(ValueError, "Preserve"):
                gguf.embed_tokenizer(original, original, b"synthetic")
            self.assertEqual(original.read_bytes(), before)


class SetupTests(unittest.TestCase):
    def test_offline_missing_asset_never_opens_network(self):
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(setup.urllib.request, "urlopen") as network:
            with self.assertRaisesRegex(RuntimeError, "missing"):
                setup.asset("https://example.com/public-model", Path(temporary) / "model", "unused", offline=True)
            network.assert_not_called()

    def test_verified_cache_never_downloads(self):
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(setup.urllib.request, "urlopen") as network:
            path = Path(temporary) / "model"
            path.write_bytes(b"synthetic")
            setup.asset("https://example.com/model", path, hashlib.sha256(b"synthetic").hexdigest())
            network.assert_not_called()

    def test_malicious_archive_link_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "runtime.tar"
            with tarfile.open(archive, "w") as file:
                entry = tarfile.TarInfo("escape")
                entry.type, entry.linkname = tarfile.SYMTYPE, "../outside"
                file.addfile(entry)
            with self.assertRaisesRegex(ValueError, "escapes"):
                setup.extract_sdk(archive, root / "destination")


class FakeProcess:
    def __init__(self):
        self.alive, self.terminated = True, False
    def is_alive(self):
        return self.alive
    def terminate(self):
        self.alive, self.terminated = False, True
    def join(self, timeout):
        pass


class StreamingTests(unittest.TestCase):
    def worker(self):
        worker = fast.FastInferenceWorker()
        worker.process, worker.pipe = FakeProcess(), types.SimpleNamespace(close=lambda: None)
        worker.phase, worker.message = "ready", "Ready"
        return worker

    def test_stream_flushes_every_frame_before_finishing(self):
        worker = self.worker()
        commands, acknowledgements = [], []
        def call(pipe, command):
            commands.append(command)
            return {"text": "synthetic final word"} if command["action"] == "finish" else {"success": True}
        worker._call = call
        sender, receiver = socket.socketpair()
        try:
            sender.sendall(struct.pack("<I", 4) + b"\1\0\2\0" + struct.pack("<I", 2) + b"\3\0" + b"\0" * 4)
            result = worker.stream(receiver, "synthetic-id", ["Lumora"], acknowledgements.append)
            self.assertEqual(result["text"], "synthetic final word")
            self.assertEqual([c["action"] for c in commands], ["begin", "audio", "audio", "finish"])
            self.assertEqual(commands[0]["vocabulary"], ["Lumora"])
            self.assertEqual(commands[2]["pcm"], b"\3\0")
            self.assertEqual(len(acknowledgements), 1)
            self.assertIsNone(worker.active_id)
            self.assertFalse(worker.process.terminated)
        finally:
            sender.close(); receiver.close()

    def test_bad_audio_and_disconnect_reap_only_owned_child(self):
        for payload in (struct.pack("<I", 32002), struct.pack("<I", 3), struct.pack("<I", 4) + b"\0"):
            worker = self.worker()
            process = worker.process
            worker._call = lambda pipe, command: {"success": True}
            sender, receiver = socket.socketpair()
            try:
                sender.sendall(payload)
                sender.shutdown(socket.SHUT_WR)
                with self.assertRaises((ValueError, ConnectionError)):
                    worker.stream(receiver, "id", [], lambda value: None)
                self.assertTrue(process.terminated)
                self.assertEqual(worker.status()["status"], "unavailable")
                self.assertIsNone(worker.active_id)
            finally:
                sender.close(); receiver.close()

    def test_cancel_can_overtake_begin_without_decoding(self):
        worker = self.worker()
        worker._call = mock.Mock()
        worker.cancel("id")
        with self.assertRaisesRegex(RuntimeError, "canceled"):
            worker.stream(None, "id", [], lambda value: None)
        worker._call.assert_not_called()
        self.assertFalse(worker.process.terminated)

    def test_active_cancel_terminates_owned_worker(self):
        worker = self.worker()
        process = worker.process
        worker.active_id = "id"
        worker.cancel("id")
        self.assertTrue(process.terminated)
        self.assertEqual(worker.phase, "unavailable")

    def test_terms_are_complete_deduplicated_and_bounded(self):
        self.assertEqual(fast.boost_terms(["Lumora", "lumora", " Acmetron ", "", "a\0b", 42]), ["Lumora", "Acmetron"])
        terms = fast.boost_terms([f"word{i}" for i in range(300)])
        self.assertEqual(len(terms), 256)
        self.assertEqual(terms[-1], "word255")

    def test_python_worker_blocks_network_and_dns(self):
        fast.deny_network("socket.__new__", (None, socket.AF_UNIX))
        for event, args in (("socket.__new__", (None, socket.AF_INET)), ("socket.getaddrinfo", ())):
            with self.assertRaises(OSError):
                fast.deny_network(event, args)


if __name__ == "__main__":
    unittest.main()
