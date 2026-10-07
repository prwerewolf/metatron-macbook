"""Privacy gates are tested in isolated repositories with synthetic data."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "privacy_check.py"
spec = importlib.util.spec_from_file_location("privacy_check", SCRIPT)
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="privacy-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.env = dict(os.environ)
        for name in list(self.env):
            if name.startswith("GIT_"):
                del self.env[name]
        self.env.update({
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": privacy.PUBLIC_NAME,
            "GIT_AUTHOR_EMAIL": privacy.PUBLIC_EMAIL,
            "GIT_COMMITTER_NAME": privacy.PUBLIC_NAME,
            "GIT_COMMITTER_EMAIL": privacy.PUBLIC_EMAIL,
        })
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env,
                              check=True, capture_output=True, text=True)

    def check(self, *args, env=None):
        return subprocess.run([sys.executable, "-B", str(SCRIPT), *args],
                              cwd=self.repo, env=env or self.env,
                              capture_output=True, text=True)

    def test_staged_content_is_checked_even_when_working_file_is_clean(self):
        # Build the synthetic token at runtime so this fixture is safe to publish.
        token = "gh" + "p_" + "x" * 36
        file = self.repo / "source.txt"
        file.write_text(token)
        self.git("add", "source.txt")
        file.write_text("safe working tree")
        result = self.check("--staged")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(token, result.stderr)
        self.assertIn("credential token", result.stderr)

    def test_force_added_private_file_is_blocked(self):
        (self.repo / ".gitignore").write_text(".env\n")
        (self.repo / ".env").write_text("ordinary text")
        self.git("add", "-f", ".env")
        result = self.check("--staged")
        self.assertEqual(result.returncode, 1)
        self.assertIn("private or generated file", result.stderr)

    def test_private_ancestor_is_blocked_after_latest_snapshot_is_clean(self):
        private = "/" + "Users/" + "sample-owner/project"
        file = self.repo / "source.txt"
        file.write_text(private)
        self.git("add", "source.txt")
        self.git("commit", "-qm", "Earlier version")
        file.write_text("safe now")
        self.git("commit", "-qam", "Clean latest version")
        self.assertEqual(self.check().returncode, 0)
        result = self.check("--history", "--ref", "HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("machine-specific home path", result.stderr)
        self.assertNotIn(private, result.stderr)

    def test_neutral_commit_identity_is_required(self):
        (self.repo / "source.txt").write_text("safe")
        self.git("add", "source.txt")
        custom = dict(self.env, GIT_AUTHOR_NAME="Sample Author")
        result = self.check("--staged", "--author", env=custom)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Sample Author", result.stderr)
        self.assertEqual(self.check("--staged", "--author").returncode, 0)

    def test_historical_private_filename_with_identical_safe_blob_is_blocked(self):
        (self.repo / "safe.txt").write_text("identical harmless content")
        self.git("add", "safe.txt")
        self.git("commit", "-qm", "Safe original blob")
        (self.repo / ".env").write_text("identical harmless content")
        self.git("add", ".env")
        self.git("commit", "-qm", "Private path sharing the same blob")
        self.git("rm", ".env")
        self.git("commit", "-qm", "Clean current snapshot")
        self.assertEqual(self.check().returncode, 0)
        result = self.check("--history", "--ref", "HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("private or generated file in history", result.stderr)

    def test_personal_commit_metadata_is_blocked(self):
        (self.repo / "source.txt").write_text("safe")
        self.git("add", "source.txt")
        self.git("commit", "-qm", "Synthetic metadata", "--author=Sample Author <author@example.com>")
        result = self.check("--history", "--ref", "HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("non-public commit identity", result.stderr)

    def test_hook_install_preserves_a_shared_global_hooks_preference(self):
        global_config = self.repo / "shared-settings"
        original = "[core]\n\thooksPath = existing-hooks\n"
        global_config.write_text(original)
        custom = dict(self.env, GIT_CONFIG_GLOBAL=str(global_config))
        result = subprocess.run(["bash", str(ROOT / "scripts" / "install_hooks.sh")],
                                cwd=self.repo, env=custom, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(global_config.read_text(), original)
        local = subprocess.run(["git", "config", "--local", "--get", "core.hooksPath"],
                               cwd=self.repo, env=custom, capture_output=True, text=True)
        self.assertEqual(local.returncode, 1)

    def copy_checkout_guards(self, destination):
        for name in (
            ".gitignore", ".githooks/pre-commit", ".githooks/pre-push",
            "scripts/privacy_check.py", "scripts/install_hooks.sh", "scripts/prepare_checkout.sh",
        ):
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)

    def test_setup_preparation_installs_hooks_in_its_own_checkout(self):
        self.copy_checkout_guards(self.repo)
        result = subprocess.run(["bash", "scripts/prepare_checkout.sh"], cwd=self.repo,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("config", "--local", "--get", "core.hooksPath").stdout.strip(), ".githooks")
        config = self.repo / privacy.LOCAL_CONFIG
        self.assertTrue(config.is_file())
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.git("check-ignore", privacy.LOCAL_CONFIG).stdout.strip(), privacy.LOCAL_CONFIG)
        self.assertEqual(self.check().returncode, 0)

    def test_source_archive_never_changes_an_enclosing_repositorys_hooks(self):
        archive = self.repo / "source-archive"
        self.copy_checkout_guards(archive)
        result = subprocess.run(["bash", "scripts/prepare_checkout.sh"], cwd=archive,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Source archive", result.stdout)
        self.assertFalse((archive / ".git").exists())
        self.assertFalse((archive / privacy.LOCAL_CONFIG).exists())
        local = subprocess.run(["git", "config", "--local", "--get", "core.hooksPath"],
                               cwd=self.repo, env=self.env, capture_output=True, text=True)
        self.assertEqual(local.returncode, 1)

    def test_setup_preparation_preserves_existing_hook_preferences(self):
        self.copy_checkout_guards(self.repo)
        self.git("config", "core.hooksPath", "existing-hooks")
        result = subprocess.run(["bash", "scripts/prepare_checkout.sh"], cwd=self.repo,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.git("config", "--local", "--get", "core.hooksPath").stdout.strip(), "existing-hooks")

    def test_invalid_git_metadata_cannot_silently_skip_the_guards(self):
        self.copy_checkout_guards(self.repo)
        shutil.rmtree(self.repo / ".git")
        (self.repo / ".git").write_text("gitdir: missing-metadata\n")
        result = subprocess.run(["bash", "scripts/prepare_checkout.sh"], cwd=self.repo,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not be verified", result.stdout)
        self.assertEqual((self.repo / ".git").read_text(), "gitdir: missing-metadata\n")

    def test_common_system_account_names_do_not_poison_the_private_identity_list(self):
        self.git("config", "user.name", privacy.PUBLIC_NAME)
        self.git("config", "user.email", privacy.PUBLIC_EMAIL)
        from unittest import mock
        with mock.patch.object(privacy.getpass, "getuser", return_value="user"):
            previous = Path.cwd()
            try:
                os.chdir(self.repo)
                privacy.initialize_local_config(self.repo)
            finally:
                os.chdir(previous)
        terms = json.loads((self.repo / privacy.LOCAL_CONFIG).read_text())["deny_terms"]
        self.assertNotIn("user", terms)
        self.assertIn(str(Path.home()), terms)
        self.assertTrue(privacy.content_findings(str(Path.home()).encode(), terms))

    def test_historical_symlink_is_detected_even_with_an_identical_regular_blob(self):
        file = self.repo / "safe.txt"
        file.write_text("target")
        self.git("add", "safe.txt")
        self.git("commit", "-qm", "Regular file")
        file.unlink()
        file.symlink_to("target")
        self.git("add", "safe.txt")
        self.git("commit", "-qm", "Symlink using the same blob")
        file.unlink()
        file.write_text("target")
        self.git("add", "safe.txt")
        self.git("commit", "-qm", "Regular file restored")
        result = self.check("--history", "--ref", "HEAD")
        self.assertEqual(result.returncode, 1)
        self.assertIn("symlink or submodule in history", result.stderr)

    def test_local_identity_list_stays_ignored_and_values_are_redacted(self):
        phrase = "Synthetic Private Identity"
        (self.repo / ".gitignore").write_text(privacy.LOCAL_CONFIG + "\n")
        (self.repo / privacy.LOCAL_CONFIG).write_text(json.dumps({"deny_terms": [phrase]}))
        file = self.repo / "source.txt"
        file.write_text(phrase)
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(phrase, result.stderr)
        self.assertNotIn(privacy.LOCAL_CONFIG + ":", result.stderr)
        file.write_text("safe")
        self.assertEqual(self.check().returncode, 0)

    def test_examples_and_icon_filenames_are_allowed(self):
        self.assertFalse(privacy.content_findings(b"user@example.com"))
        self.assertFalse(privacy.content_findings(b"icon_16x16@2x.png"))
        self.assertTrue(privacy.content_findings(b"user@" + b"actual-mail.test"))

    def test_push_hook_blocks_old_ancestry(self):
        file = self.repo / "source.txt"
        file.write_text("safe")
        self.git("add", "source.txt")
        self.git("commit", "-qm", "Clean public start")
        oid = self.git("rev-parse", "HEAD").stdout.strip()
        (self.repo / "scripts").mkdir()
        (self.repo / "scripts" / "privacy_check.py").write_bytes(SCRIPT.read_bytes())
        hook = ROOT / ".githooks" / "pre-push"
        payload = f"refs/heads/main {oid} refs/heads/main {'0' * 40}\n"
        result = subprocess.run(["bash", str(hook)], input=payload, cwd=self.repo,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        file.write_text("/" + "home/" + "sample-owner/project")
        self.git("commit", "-qam", "Unsafe ancestor")
        file.write_text("safe again")
        self.git("commit", "-qam", "Clean snapshot")
        oid = self.git("rev-parse", "HEAD").stdout.strip()
        payload = f"refs/heads/main {oid} refs/heads/main {'0' * 40}\n"
        result = subprocess.run(["bash", str(hook)], input=payload, cwd=self.repo,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
