"""First-run model selection uses temporary caches and a mocked downloader."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("setup_model", ROOT / "scripts" / "setup_model.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def model(self, folder):
        folder.mkdir(parents=True)
        (folder / "config.json").write_text("{}")
        (folder / "weights.safetensors").write_bytes(b"synthetic weights")
        return folder

    def test_cache_environment_precedence(self):
        env = {"XDG_CACHE_HOME": "/cache", "HF_HOME": "/hf", "HF_HUB_CACHE": "/hub",
               "HUGGINGFACE_HUB_CACHE": "/legacy"}
        self.assertEqual(setup.cache_root(env), Path("/hub"))
        del env["HF_HUB_CACHE"]
        self.assertEqual(setup.cache_root(env), Path("/legacy"))
        del env["HUGGINGFACE_HUB_CACHE"]
        self.assertEqual(setup.cache_root(env), Path("/hf/hub"))
        del env["HF_HOME"]
        self.assertEqual(setup.cache_root(env), Path("/cache/huggingface/hub"))

    def test_offline_missing_model_never_calls_downloader(self):
        with tempfile.TemporaryDirectory() as temporary:
            download = mock.Mock()
            with self.assertRaisesRegex(RuntimeError, "No complete local model"):
                setup.prepare_model(environment={"HF_HUB_CACHE": temporary}, downloader=download)
            download.assert_not_called()

    def test_existing_model_avoids_download_even_during_online_setup(self):
        with tempfile.TemporaryDirectory() as temporary:
            model = self.model(Path(temporary) / "models--mlx-community--whisper-large-v3-turbo" / "snapshots" / "ready")
            download = mock.Mock()
            self.assertEqual(setup.prepare_model(True, {"HF_HUB_CACHE": temporary}, download), model.resolve())
            download.assert_not_called()

    def test_explicit_invalid_model_never_silently_downloads(self):
        with tempfile.TemporaryDirectory() as temporary:
            download = mock.Mock()
            with self.assertRaisesRegex(RuntimeError, "explicitly configured"):
                setup.prepare_model(True, {"PRESSTOWRITE_MODEL_DIR": temporary}, download)
            download.assert_not_called()

    def test_cached_fallback_model_is_usable(self):
        with tempfile.TemporaryDirectory() as temporary:
            model = self.model(Path(temporary) / "models--mlx-community--whisper-base.en" / "snapshots" / "ready")
            self.assertEqual(setup.prepare_model(environment={"HF_HUB_CACHE": temporary}), model.resolve())

    def test_explicit_download_is_limited_to_model_files_and_uses_no_token(self):
        with tempfile.TemporaryDirectory() as temporary:
            model = self.model(Path(temporary) / "downloaded")
            download = mock.Mock(return_value=str(model))
            self.assertEqual(setup.prepare_model(True, {"HF_HOME": temporary}, download), model)
            kwargs = download.call_args.kwargs
            self.assertEqual(kwargs["repo_id"], setup.DEFAULT_MODEL)
            self.assertFalse(kwargs["token"])
            self.assertIn("weights.safetensors", kwargs["allow_patterns"])
            self.assertNotIn("*", kwargs["allow_patterns"])

    def test_incomplete_download_cannot_report_setup_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(RuntimeError, "download is incomplete"):
                setup.prepare_model(True, {"HF_HUB_CACHE": temporary}, mock.Mock(return_value=temporary))


if __name__ == "__main__":
    unittest.main()
