#!/usr/bin/env python3
"""Resident, strictly offline MLX speech recognition over a local Unix socket."""

import os

# These must be set before importing MLX or any Hugging Face dependency.
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"

import sys
import errno
import re
import json
import time
import socket
import signal
import threading
import hashlib
import fcntl
import multiprocessing
import queue
import stat
import wave
from concurrent.futures import Future
from pathlib import Path

SOCKET_PATH = "/tmp/metatron.sock"
DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
FALLBACK_MODEL = "mlx-community/whisper-base.en"
PROTOCOL_VERSION = 3
MAX_REQUEST_BYTES = 65536
SCRIPT_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

active_model = None
active_model_path = None
mlx_whisper = None
is_engine_ready = False
engine_load_error = None
engine_message = "Loading the local speech model…"
engine_lock = threading.Lock()
inference_lock = threading.Lock()
server_stop = threading.Event()
bound_socket_identity = None


def deny_network_access(event, args):
    """Defense in depth: this daemon permits Unix sockets, never network sockets."""
    if event == "socket.__new__" and args[1] in (socket.AF_INET, socket.AF_INET6):
        raise OSError("Metatron speech recognition is offline; network access is disabled")
    if event in ("socket.getaddrinfo", "socket.gethostbyname", "socket.gethostbyaddr"):
        raise OSError("Metatron speech recognition is offline; DNS access is disabled")


def complete_model_folder(folder):
    folder = Path(folder)
    try:
        return (folder / "config.json").is_file() and any(
            (folder / name).is_file() and (folder / name).stat().st_size > 0
            for name in ("weights.safetensors", "weights.npz")
        )
    except OSError:
        return False


def local_model_candidates():
    """Find downloaded files directly; never invoke a Hub resolver or downloader."""
    explicit_path = os.environ.get("METATRON_MODEL_DIR")
    if explicit_path:
        folder = Path(explicit_path).expanduser().resolve()
        if not complete_model_folder(folder):
            raise RuntimeError(f"The local model folder is incomplete: {folder}")
        return [(folder.name, str(folder))]

    cache_home = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))).expanduser()
    hf_home = Path(os.environ.get("HF_HOME", str(cache_home / "huggingface"))).expanduser()
    hub_cache = Path(os.environ.get("HF_HUB_CACHE", os.environ.get(
        "HUGGINGFACE_HUB_CACHE", str(hf_home / "hub")
    ))).expanduser()
    candidates = []
    for model in (DEFAULT_MODEL, FALLBACK_MODEL):
        repository = hub_cache / ("models--" + model.replace("/", "--"))
        snapshots = repository / "snapshots"
        folders = []
        main_ref = repository / "refs" / "main"
        if main_ref.is_file():
            revision = main_ref.read_text().strip()
            if revision and "/" not in revision and revision not in (".", ".."):
                folders.append(snapshots / revision)
        if snapshots.is_dir():
            folders.extend(sorted(snapshots.iterdir(), key=lambda path: path.name))
        for folder in folders:
            if complete_model_folder(folder):
                candidates.append((model, str(folder.resolve())))
                break
    if not candidates:
        raise RuntimeError(
            "No downloaded speech model was found. Install a local MLX Whisper model "
            "and restart Metatron. No model will be downloaded automatically."
        )
    return candidates


def engine_status():
    with engine_lock:
        return {
            "success": True,
            "protocol_version": PROTOCOL_VERSION,
            "script_sha256": SCRIPT_SHA256,
            "pid": os.getpid(),
            "offline": True,
            "status": "ready" if is_engine_ready else ("unavailable" if engine_load_error else "loading"),
            "message": engine_load_error or engine_message,
            "model": active_model,
        }


def load_engine_background():
    global mlx_whisper, active_model, active_model_path
    global is_engine_ready, engine_load_error, engine_message
    with engine_lock:
        is_engine_ready = False
        engine_load_error = None
        engine_message = "Loading the local speech model…"
    try:
        candidates = local_model_candidates()
        import mlx_whisper as mw
        import numpy as np

        failures = []
        # All MLX work runs on the same single worker, including this warmup. Passing
        # an existing directory also prevents mlx-whisper from calling snapshot_download.
        with inference_lock:
            for model, model_path in candidates:
                try:
                    with engine_lock:
                        active_model = model
                        engine_message = "Warming up the local speech model…"
                    mw.transcribe(
                        np.zeros(16000, dtype=np.float32),
                        path_or_hf_repo=model_path,
                        fp16=True,
                        verbose=None,
                        language="en",
                        temperature=0.0,
                        sample_len=1,
                        condition_on_previous_text=False,
                    )
                    with engine_lock:
                        mlx_whisper = mw
                        active_model_path = model_path
                        is_engine_ready = True
                        engine_message = "Ready — speech stays on this Mac"
                    print(f"[Metatron Daemon] Local model loaded and warmed: {model}")
                    return
                except Exception as error:
                    failures.append(f"{model}: {error}")
        raise RuntimeError("Unable to load the downloaded speech model. " + "; ".join(failures))
    except Exception as error:
        with engine_lock:
            engine_load_error = str(error)
        print(f"[Metatron Daemon] Local model unavailable: {error}", file=sys.stderr)


def deduplicate_repetition_loops(text: str) -> str:
    if not text:
        return ""
    # 1. Deduplicate repeated sentences or clauses with ending punctuation (e.g. "Phrase. Phrase. Phrase." -> "Phrase.")
    text = re.sub(r"(?<![\w'’-])((?:[^\.\?\!\n]+?[\.\?\!]))(?:\s+\1)+", r'\1', text, flags=re.IGNORECASE)
    # 2. Deduplicate repeated multi-word phrases (2 to 8 words) (e.g. "phrase phrase phrase" -> "phrase")
    # Match whole words, including at the start of the first phrase and the end
    # of every repeat: "do you do your homework" must not become "do your homework".
    text = re.sub(r"(?<![\w'’-])((?:[a-zA-Z0-9']+[,\s]+){1,8}[a-zA-Z0-9']+)(?:[,\s]+\1(?![\w'’-]))+", r'\1', text, flags=re.IGNORECASE)
    return text.strip()

def clean_whisper_result(result: dict) -> str:
    segments = result.get("segments", [])
    if segments:
        cleaned_segments = []
        for seg in segments:
            seg_text = seg.get("text", "").strip()
            if not seg_text:
                continue

            # Check compression ratio: Whisper flags repetitive hallucination with high ratio
            comp_ratio = seg.get("compression_ratio", 1.0)
            if comp_ratio and comp_ratio > 2.4:
                continue

            # Skip segments flagged as silence/low confidence
            no_speech = seg.get("no_speech_prob", 0.0)
            avg_logprob = seg.get("avg_logprob", 0.0)
            if no_speech and no_speech > 0.6 and avg_logprob and avg_logprob < -1.0:
                continue

            # Filter consecutive duplicate segments
            if cleaned_segments and seg_text.lower() == cleaned_segments[-1].lower():
                continue

            cleaned_segments.append(seg_text)

        raw_text = " ".join(cleaned_segments).strip() if cleaned_segments else ""
    else:
        raw_text = result.get("text", "").strip()

    return deduplicate_repetition_loops(raw_text)

def vocabulary_prompt(vocabulary):
    """Keep a compact, stable hint within Whisper's limited initial prompt context."""
    if not isinstance(vocabulary, list):
        raise ValueError("Vocabulary must be a list of words or phrases")
    terms = []
    seen = set()
    length = 0
    for value in vocabulary:
        if not isinstance(value, str):
            raise ValueError("Vocabulary terms must be text")
        term = " ".join(value.split()).strip()[:100]
        if not term or term.casefold() in seen:
            continue
        if len(terms) >= 50 or length + len(term) + 2 > 500:
            break
        terms.append(term)
        seen.add(term.casefold())
        length += len(term) + 2
    return ", ".join(terms) if terms else None


def load_recorded_audio(audio_path):
    """Decode Metatron's 16 kHz mono PCM16 WAV without invoking ffmpeg."""
    with wave.open(audio_path, "rb") as recording:
        if (recording.getnchannels() != 1 or recording.getframerate() != 16000
                or recording.getsampwidth() != 2 or recording.getcomptype() != "NONE"):
            raise ValueError("Unsupported recording format; expected 16 kHz mono PCM16 WAV")
        pcm = recording.readframes(recording.getnframes())
    if not pcm:
        raise ValueError("The recording contains no audio samples")

    import numpy as np
    # WAV PCM is little-endian. astype makes a writable float32 copy before scaling.
    return np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0


def transcribe_file(audio_path: str, vocabulary=None, style="natural") -> dict:
    if style not in ("natural", "professional", "raw"):
        return {"error": "Unknown writing style"}
    try:
        prompt = vocabulary_prompt([] if vocabulary is None else vocabulary)
    except ValueError as error:
        return {"error": str(error)}

    status = engine_status()
    if status["status"] != "ready":
        return {"error": status["message"]}
    if not isinstance(audio_path, str) or not os.path.isfile(audio_path):
        return {"error": "The temporary audio recording could not be found"}

    start_time = time.monotonic()
    try:
        with inference_lock:
            # Recheck that files still exist. Even a removed cache must never turn
            # into a Hub lookup. Offline flags + the network guard enforce this too.
            if not active_model_path or not complete_model_folder(active_model_path):
                raise RuntimeError("The downloaded speech model is missing. Restart Metatron after restoring it.")
            audio = load_recorded_audio(audio_path)
            result = mlx_whisper.transcribe(
                audio,
                path_or_hf_repo=active_model_path,
                fp16=True,
                verbose=None,
                initial_prompt=prompt,
                condition_on_previous_text=False,
                compression_ratio_threshold=2.4,
                logprob_threshold=-1.0,
                no_speech_threshold=0.6,
            )
        # Return the recognizer's text exactly. Swift owns style-specific cleanup
        # in one place; Raw bypasses that cleanup completely.
        text = result.get("text", "")
        return {
            "success": True,
            "text": text,
            "duration": round(time.monotonic() - start_time, 3),
            "model": active_model,
        }
    except Exception as error:
        return {"error": str(error)}
    finally:
        # Ephemeral recordings are removed even when recognition fails.
        try:
            os.remove(audio_path)
        except OSError:
            pass


def _remove_recording(path):
    try:
        os.remove(path)
    except OSError:
        pass


def inference_process(pipe):
    """MLX lives only in this child so an abandoned decode can be stopped safely."""
    sys.addaudithook(deny_network_access)
    try:
        load_engine_background()
        pipe.send({"kind": "status", "status": engine_status()})
        while True:
            message = pipe.recv()
            if message.get("action") != "transcribe":
                continue
            result = transcribe_file(
                message["path"], message.get("vocabulary", []), message.get("style", "natural")
            )
            pipe.send({"kind": "result", "request_id": message["request_id"], "result": result})
    except (EOFError, BrokenPipeError):
        pass
    finally:
        pipe.close()


class IsolatedInferenceWorker:
    """One warm MLX child. Cancellation terminates only that owned child."""

    def __init__(self, context=None):
        self.context = context or multiprocessing.get_context("spawn")
        self.pending = queue.Queue()
        self.jobs = {}
        self.cancelled_ids = {}
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.process = None
        self.thread = threading.Thread(target=self._run, name="metatron-inference-supervisor", daemon=True)
        self.thread.start()

    def submit(self, request_id, path, vocabulary, style):
        future = Future()
        job = {"request_id": request_id, "path": path, "vocabulary": vocabulary,
               "style": style, "future": future, "cancelled": threading.Event()}
        with self.lock:
            if request_id in self.jobs:
                raise ValueError("A transcription with that request ID is already running")
            if request_id in self.cancelled_ids:
                self.cancelled_ids.pop(request_id)
                _remove_recording(path)
                future.set_result({"error": "Dictation canceled"})
                return future
            self.jobs[request_id] = job
        self.pending.put(job)
        return future

    def cancel(self, request_id):
        with self.lock:
            job = self.jobs.get(request_id)
            if job is None:
                # Cancellation can overtake request delivery on a second socket.
                # Keep a small, short-lived tombstone for that race.
                now = time.monotonic()
                self.cancelled_ids = {key: expiry for key, expiry in self.cancelled_ids.items() if expiry > now}
                if len(self.cancelled_ids) >= 128:
                    self.cancelled_ids.pop(next(iter(self.cancelled_ids)))
                self.cancelled_ids[request_id] = now + 10
                return True
            job["cancelled"].set()
            if not job["future"].done():
                job["future"].set_result({"error": "Dictation canceled"})
        return True

    def shutdown(self):
        self.stopping.set()
        with self.lock:
            process = self.process
        if process is not None and process.is_alive():
            process.terminate()
        self.thread.join(timeout=2)

    def _finish(self, job, result):
        with self.lock:
            self.jobs.pop(job["request_id"], None)
            if not job["future"].done():
                job["future"].set_result(result)

    def _run(self):
        global is_engine_ready, engine_load_error, engine_message, active_model
        while not self.stopping.is_set():
            with engine_lock:
                is_engine_ready = False
                engine_load_error = None
                engine_message = "Loading the local speech model…"
                active_model = None
            parent_pipe, child_pipe = self.context.Pipe()
            process = self.context.Process(target=inference_process, args=(child_pipe,), daemon=True)
            try:
                process.start()
            except Exception as error:
                with engine_lock:
                    engine_load_error = f"Could not start the local speech worker: {error}"
                parent_pipe.close()
                child_pipe.close()
                if self.stopping.wait(1):
                    break
                continue
            child_pipe.close()
            with self.lock:
                self.process = process
            active_job = None
            try:
                while not self.stopping.is_set() and process.is_alive():
                    if active_job is not None and active_job["cancelled"].is_set():
                        # The inference call is synchronous and cannot be interrupted in
                        # its thread. Reap the owned child and warm a fresh one.
                        break
                    try:
                        if parent_pipe.poll(0.05):
                            message = parent_pipe.recv()
                            if message.get("kind") == "status":
                                status = message["status"]
                                with engine_lock:
                                    is_engine_ready = status["status"] == "ready"
                                    engine_load_error = status["message"] if status["status"] == "unavailable" else None
                                    engine_message = status["message"]
                                    active_model = status["model"]
                            elif message.get("kind") == "result" and active_job is not None:
                                self._finish(active_job, message["result"])
                                active_job = None
                    except (EOFError, BrokenPipeError, OSError):
                        break
                    if active_job is None:
                        try:
                            job = self.pending.get_nowait()
                        except queue.Empty:
                            continue
                        if job["cancelled"].is_set():
                            _remove_recording(job["path"])
                            self._finish(job, {"error": "Dictation canceled"})
                            continue
                        with engine_lock:
                            ready = is_engine_ready
                            unavailable = engine_load_error
                        if unavailable:
                            _remove_recording(job["path"])
                            self._finish(job, {"error": unavailable})
                        elif not ready:
                            self.pending.put(job)
                        else:
                            try:
                                parent_pipe.send({
                                    "action": "transcribe", "request_id": job["request_id"],
                                    "path": job["path"], "vocabulary": job["vocabulary"], "style": job["style"],
                                })
                                active_job = job
                            except (BrokenPipeError, OSError):
                                self.pending.put(job)
                                break
            finally:
                if process.is_alive():
                    process.terminate()
                process.join(timeout=2)
                if process.is_alive():
                    process.kill()
                    process.join(timeout=2)
                parent_pipe.close()
                with self.lock:
                    if self.process is process:
                        self.process = None
                if active_job is not None:
                    _remove_recording(active_job["path"])
                    self._finish(active_job, {"error": "Dictation canceled" if active_job["cancelled"].is_set()
                                             else "The local speech worker stopped unexpectedly"})
            if not self.stopping.is_set():
                self.stopping.wait(0.1)


def cleanup_socket():
    """Never unlink a replacement server's socket during this daemon's exit."""
    global bound_socket_identity
    if bound_socket_identity is None:
        return
    try:
        current = os.lstat(SOCKET_PATH)
        if (current.st_dev, current.st_ino) == bound_socket_identity:
            os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass
    bound_socket_identity = None


def remove_stale_socket():
    """Called only while holding the launch lock; reject a live listener."""
    try:
        before = os.lstat(SOCKET_PATH)
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(before.st_mode):
        raise RuntimeError("The local speech socket path is occupied by another file")
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.settimeout(0.2)
        probe.connect(SOCKET_PATH)
        raise RuntimeError("Another local speech daemon is already running")
    except (ConnectionRefusedError, FileNotFoundError):
        pass
    finally:
        probe.close()
    try:
        current = os.lstat(SOCKET_PATH)
        if (current.st_dev, current.st_ino) == (before.st_dev, before.st_ino):
            os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def handle_connection(conn, worker):
    try:
        conn.settimeout(5)
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            if len(data) > MAX_REQUEST_BYTES:
                raise ValueError("Daemon request is too large")
        if not data.strip():
            return
        req = json.loads(data.split(b"\n", 1)[0])
        action = req.get("action", "")
        if action == "ping":
            response = engine_status()
        elif req.get("protocol_version") != PROTOCOL_VERSION:
            response = {"error": "Restart Metatron to update the local speech connection"}
        elif action == "transcribe":
            request_id = req.get("request_id")
            if not isinstance(request_id, str) or not re.fullmatch(r"[0-9a-fA-F-]{36}", request_id):
                raise ValueError("A valid transcription request ID is required")
            # Ping and cancel never wait behind the single MLX worker.
            response = worker.submit(
                request_id, req.get("path", ""), req.get("vocabulary", []), req.get("style", "natural")
            ).result()
        elif action == "cancel":
            response = {"success": True, "cancelled": worker.cancel(req.get("request_id"))}
        elif action == "shutdown":
            if req.get("expected_sha256") != SCRIPT_SHA256:
                response = {"error": "The speech daemon changed; shutdown was refused"}
            else:
                response = {"success": True}
                server_stop.set()
        else:
            response = {"error": f"Unknown action: {action}"}
        response["protocol_version"] = PROTOCOL_VERSION
        conn.sendall((json.dumps(response) + "\n").encode("utf-8"))
    except (BrokenPipeError, ConnectionResetError, TimeoutError):
        pass
    except Exception as error:
        try:
            conn.sendall((json.dumps({"error": str(error), "protocol_version": PROTOCOL_VERSION}) + "\n").encode("utf-8"))
        except OSError:
            pass
    finally:
        conn.close()


def start_parent_watchdog():
    parent_pid_str = os.environ.get("METATRON_PARENT_PID")
    if not parent_pid_str:
        return
    try:
        parent_pid = int(parent_pid_str)
        if parent_pid <= 1:
            return
    except ValueError:
        return

    def _watch():
        while not server_stop.is_set():
            time.sleep(1.0)
            try:
                os.kill(parent_pid, 0)
            except OSError as err:
                if err.errno == errno.ESRCH:
                    print(f"[Metatron Daemon] Parent process {parent_pid} exited. Stopping daemon.")
                    server_stop.set()
                    time.sleep(0.5)
                    os._exit(0)

    t = threading.Thread(target=_watch, daemon=True, name="ParentWatchdog")
    t.start()


def run_server():
    global bound_socket_identity
    lock_file = open(SOCKET_PATH + ".lock", "a+b")
    fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    remove_stale_socket()
    server_stop.clear()
    start_parent_watchdog()
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    bound = os.lstat(SOCKET_PATH)
    bound_socket_identity = (bound.st_dev, bound.st_ino)
    server.listen(16)
    server.settimeout(0.5)
    os.chmod(SOCKET_PATH, 0o600)
    print(f"[Metatron Daemon] Offline socket initialized at {SOCKET_PATH}")
    worker = IsolatedInferenceWorker()
    try:
        while not server_stop.is_set():
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            threading.Thread(target=handle_connection, args=(conn, worker), daemon=True).start()
    finally:
        server.close()
        cleanup_socket()
        worker.shutdown()
        lock_file.close()


if __name__ == "__main__":
    sys.addaudithook(deny_network_access)
    run_server()
