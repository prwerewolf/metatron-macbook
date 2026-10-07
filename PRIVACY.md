# Privacy and source sharing

Speech recognition runs locally. One-time setup downloads Python packages and
model files; the running speech daemon blocks network sockets and DNS and uses
only complete files already on disk. There is no cloud transcription API key.

## Local data

| Data | Storage |
| --- | --- |
| Vocabulary, snippets, microphone selection, other preferences | macOS UserDefaults for the app |
| Latest audio recording and recovery metadata | `~/Library/Application Support/Press To Write/` |
| Python environment | `~/Library/Application Support/Press To Write/venv/` |
| Speech model weights | Local Hugging Face cache or a user-selected directory |
| Diagnostic log | `/tmp/presstowrite_daemon.log` |
| Dictation history | Memory only; cleared when the app exits |

Quitting the app does not erase the recovery recording. Remove it from Application
Support yourself when you no longer want it retained. Incognito changes in-memory
history behavior; it does not disable audio recovery. Applications you dictate
into and the system clipboard can retain or sync their own copies of text.

## Files that must stay private

`.gitignore` excludes environments, app bundles, model weights, signing material,
recordings, logs, databases, private backups, environment files, and local editor
or agent configuration. Exclusion does not remove a file already tracked by Git.
The privacy checker also rejects these file types when force-added.

`make privacy` checks tracked and eligible untracked files without printing
matched values. The commit hook checks the actual staged contents. The push hook
checks all ancestors of every outgoing ref, so an older commit cannot bypass a
clean latest snapshot. GitHub Actions repeats the history and file checks.

Normal `make setup` enables the local checks in a Git clone. A source ZIP does
not initialize Git or change an enclosing repository's settings. Maintainers
can also run `make install-hooks` directly to prepare a checkout without installing
the app. This creates an ignored, owner-only
`.privacy-local.json` containing local identity terms. This file is never a
publication input. Maintainers can add private names, handles, email addresses,
and project-specific identifiers to its `deny_terms` list locally. Shared Git
preferences and app settings are not changed.

GitHub CI is automatic once the repository is published; the local checks are
active after setup on each checkout. Neither requires a Codex skill. AGENTS.md
adds standing instructions for coding agents. Keep the hooks and repository
checks enabled, use the neutral commit wrapper, and review every outgoing diff.

Automated checks detect common credentials, home paths, real email addresses,
private file types, and locally configured identity terms. They cannot recognize
every name, screenshot, transcript, or identifier. Review each staged diff and
use synthetic examples before publication. Hooks can be bypassed, and CI runs
after a push; neither is a guarantee that private data can never be uploaded.

## Historical data

Changing today's source or `.gitignore` does not scrub old commits. A history
rewrite must cover all branches, tags, commit authors, and relevant attachments.
Old clones must be replaced or separately cleaned before further updates.

GitHub can retain old commits in pull-request refs and cached views even after a
force-push. Check these separately before exposing a previously private repository.
See [GitHub's sensitive-data removal process](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
If credentials were exposed, revoke them as well. Repository ownership and
GitHub activity remain associated with the hosting account even when source and
commit identities have been sanitized.
