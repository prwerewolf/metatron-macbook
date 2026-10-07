#!/usr/bin/env python3
"""Check shareable files and Git history without printing sensitive values."""

import argparse
import fnmatch
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PUBLIC_NAME = "Press To Write Maintainers"
PUBLIC_EMAIL = "maintainers@presstowrite.invalid"
LOCAL_CONFIG = ".privacy-local.json"
GENERIC_IDENTITIES = {
    "user", "root", "runner", "admin", "administrator", "developer", "dev",
    "test", "guest", "mac", "owner",
}
ALLOWED_BINARY = {"Resources/AppIcon.icns", "Resources/AppIcon_master.png"}
PRIVATE_PARTS = {
    ".venv", ".build", ".codex", ".agents", ".aws", ".ssh", ".cache",
    ".idea", ".vscode", ".swiftpm", "private", "recordings", "transcripts",
    "history", "logs", "runtime", "models", "dist",
}
PRIVATE_GLOBS = (
    ".env", ".env.*", LOCAL_CONFIG, "*.local", "*.local.*", "*.app",
    "*.wav", "*.aiff", "*.aif", "*.caf", "*.mp3", "*.m4a", "*.flac",
    "*.log", "*.sqlite", "*.sqlite3", "*.db", "*.pem", "*.key", "*.p12",
    "*.pfx", "*.mobileprovision", "*.safetensors", "*.npz", "*.pt", "*.pth",
    "*.onnx", "*.zip", "*.dmg", "*.pkg", "*.bundle", "*.bak", "*.backup",
    "credentials*", "secrets*", "last_recording*", ".python-version",
    ".tool-versions", ".DS_Store",
)
PATTERNS = {
    "machine-specific home path": re.compile(
        r"/(?:Users|home)/[a-z0-9._-]+|[a-z]:[\\/]+Users[\\/]+[a-z0-9._-]+", re.I
    ),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "credential token": re.compile(
        r"\b(?:gh[pousr]_[a-z0-9]{20,}|github_pat_[a-z0-9_]{40,}|"
        r"sk-[a-z0-9_-]{24,}|AKIA[A-Z0-9]{16}|hf_[a-z0-9]{30,})\b", re.I
    ),
    "credential in URL": re.compile(r"[a-z][a-z0-9+.-]*://[^\s/@:]+:[^\s/@]+@", re.I),
}
EMAIL = re.compile(r"\b[a-z0-9._%+-]+@([a-z0-9.-]+\.[a-z]{2,})\b", re.I)
SECRET_ASSIGNMENT = re.compile(
    r"\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*"
    r"[\"']([a-z0-9_+/.=-]{12,})[\"']", re.I
)


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def private_path(path):
    parts = Path(path).parts
    if any(part in PRIVATE_PARTS for part in parts):
        return True
    return any(
        part != ".env.example" and any(fnmatch.fnmatch(part, pattern) for pattern in PRIVATE_GLOBS)
        for part in parts
    )


def allowed_email(domain):
    domain = domain.lower()
    return domain in {"example.com", "example.org", "example.net"} or domain.endswith(
        (".invalid", ".example")
    )


def content_findings(data, deny_terms=()):
    text = data.decode("utf-8", errors="replace")
    result = {label for label, regex in PATTERNS.items() if regex.search(text)}
    if any(
        not allowed_email(match.group(1)) and not re.fullmatch(
            r"icon_\d+x\d+@2x\.png", match.group(0)
        )
        for match in EMAIL.finditer(text)
    ):
        result.add("non-example email address")
    if any(
        not match.group(1).lower().startswith(("example", "placeholder", "your_", "test_"))
        for match in SECRET_ASSIGNMENT.finditer(text)
    ):
        result.add("possible hardcoded credential")
    normalized = re.sub(r"\\[nr]|\s+", " ", text).casefold()
    if any(term.casefold() in normalized for term in deny_terms if term):
        result.add("private local identity")
    return result


def inspect_file(path, data, deny_terms):
    result = content_findings(data, deny_terms)
    if private_path(path):
        result.add("private or generated file")
    if "\0" in data.decode("utf-8", errors="replace") and path not in ALLOWED_BINARY:
        result.add("unreviewed binary file")
    if len(data) > 5 * 1024 * 1024 and path not in ALLOWED_BINARY:
        result.add("oversized file")
    if content_findings(path.encode(), deny_terms):
        result.add("personal data in filename")
    return result


def initialize_local_config(root):
    """Keep owner-specific deny terms outside the published source."""
    path = root / LOCAL_CONFIG
    if path.exists():
        return
    terms = {getpass.getuser(), str(Path.home())}
    # Learn only the local Git identity; never print it or change Git preferences.
    for field in ("user.name", "user.email"):
        try:
            value = git("config", "--get", field).decode().strip()
        except subprocess.CalledProcessError:
            continue
        if value not in {PUBLIC_NAME, PUBLIC_EMAIL}:
            terms.add(value)
    # Common system account labels also occur throughout ordinary source code.
    # Home paths and real commit identities remain independently guarded.
    terms = {term for term in terms if len(term) >= 3 and term.casefold() not in GENERIC_IDENTITIES}
    payload = json.dumps({"deny_terms": sorted(terms)}, indent=2) + "\n"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(payload)


def load_deny_terms(root):
    path = root / LOCAL_CONFIG
    if not path.exists():
        return []
    payload = json.loads(path.read_text())
    terms = payload.get("deny_terms", [])
    if not isinstance(terms, list) or not all(isinstance(term, str) for term in terms):
        raise ValueError("Local privacy configuration must contain a list of deny_terms")
    return terms


def snapshot_files(root, staged=False):
    if staged:
        for entry in git("ls-files", "--stage", "-z").split(b"\0"):
            if not entry:
                continue
            metadata, path = entry.split(b"\t", 1)
            mode, oid, stage = metadata.split()
            if stage != b"0":
                raise ValueError("Resolve merge conflicts before checking staged files")
            if mode not in {b"100644", b"100755"}:
                raise ValueError("Symlinks and submodules require a separate privacy review")
            yield path.decode(), git("cat-file", "blob", oid.decode())
    else:
        paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
        for entry in sorted(set(paths.split(b"\0")) - {b""}):
            path = entry.decode()
            file = root / path
            if file.is_symlink():
                raise ValueError("Symlinks require a separate privacy review")
            if file.is_file():
                yield path, file.read_bytes()


def history_files(refs):
    seen = set()
    for entry in git("rev-list", "--objects", *refs).decode().splitlines():
        oid, separator, path = entry.partition(" ")
        if not separator or oid in seen:
            continue
        seen.add(oid)
        if git("cat-file", "-t", oid).strip() == b"blob":
            yield path, git("cat-file", "blob", oid)


def history_identity_findings(refs, deny_terms):
    failures = []
    expected = f"{PUBLIC_NAME} <{PUBLIC_EMAIL}>"
    for oid in git("rev-list", *refs).decode().splitlines():
        raw = git("cat-file", "commit", oid).decode()
        header, _, message = raw.partition("\n\n")
        labels = content_findings(message.encode(), deny_terms)
        for line in header.splitlines():
            if line.startswith(("author ", "committer ")):
                identity = line.split(" ", 1)[1].rsplit(" ", 2)[0]
                if identity != expected:
                    labels.add("non-public commit identity")
        if labels:
            failures.append(("commit " + oid[:10], labels))
    return failures


def history_path_findings(refs, deny_terms):
    # rev-list --objects assigns only one path to a shared blob. Inspect trees
    # as well so a private filename cannot hide behind an identical safe file.
    failures = []
    seen = set()
    trees = set(git("log", "--format=%T", *refs).decode().splitlines())
    for tree in trees:
        for entry in git("ls-tree", "-r", "-z", tree).split(b"\0"):
            if not entry:
                continue
            metadata, raw_path = entry.split(b"\t", 1)
            mode, kind, oid = metadata.split()
            path = raw_path.decode()
            if (path, mode) in seen:
                continue
            seen.add((path, mode))
            labels = set()
            if private_path(path):
                labels.add("private or generated file in history")
            if mode not in {b"100644", b"100755"}:
                labels.add("symlink or submodule in history")
            if content_findings(raw_path, deny_terms):
                labels.add("personal data in historical filename")
            if labels:
                label = "[private filename]" if content_findings(raw_path, deny_terms) else path
                failures.append((label, labels))
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--staged", action="store_true", help="Inspect the actual Git index")
    modes.add_argument("--history", action="store_true", help="Inspect reachable blobs and commit identities")
    parser.add_argument("--ref", action="append", help="History ref to inspect (default: all local refs)")
    parser.add_argument("--author", action="store_true", help="Require the neutral identity for the next commit")
    parser.add_argument("--init-local", action="store_true", help="Create ignored owner-specific checks without changing preferences")
    args = parser.parse_args(argv)
    try:
        root = Path(git("rev-parse", "--show-toplevel").decode().strip())
        if args.ref and not args.history:
            parser.error("--ref requires --history")
        if args.init_local:
            initialize_local_config(root)
        terms = load_deny_terms(root)
        refs = args.ref or ["--all"]
        files = history_files(refs) if args.history else snapshot_files(root, args.staged)
        failures = []
        count = 0
        for path, data in files:
            count += 1
            labels = inspect_file(path, data, terms)
            if labels:
                # Do not reveal a filename containing private data either.
                label = "[private filename]" if content_findings(path.encode(), terms) else path
                failures.append((label, labels))
        if args.history:
            failures.extend(history_identity_findings(refs, terms))
            failures.extend(history_path_findings(refs, terms))
        if args.author:
            identity = git("var", "GIT_AUTHOR_IDENT").decode().strip().rsplit(" ", 2)[0]
            committer = git("var", "GIT_COMMITTER_IDENT").decode().strip().rsplit(" ", 2)[0]
            expected = f"{PUBLIC_NAME} <{PUBLIC_EMAIL}>"
            if identity != expected or committer != expected:
                failures.append(("next commit", {"non-public commit identity; use scripts/commit.sh"}))
        if failures:
            print("Privacy check blocked publication:", file=sys.stderr)
            for path, labels in failures:
                print(f"  {path}: {', '.join(sorted(labels))}", file=sys.stderr)
            return 1
        print(f"Privacy check passed ({count} file versions).")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        # Command stderr and configuration values can themselves contain secrets.
        print(f"Privacy check could not complete ({type(error).__name__}); publication blocked.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
