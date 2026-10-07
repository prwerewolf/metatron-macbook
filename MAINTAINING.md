# Maintainer updates

These instructions are for the copyright holder or explicitly authorized
maintainers. The license does not grant community users permission to modify
or redistribute the application. Bug reports using synthetic examples are welcome.

## Prepare a checkout

Use a fresh clone of the official repository after any history rewrite. Preserve
local preferences and keep app data outside the repository. Normal `make setup`
automatically installs the local commit and push checks in this application's own
Git checkout. To prepare a maintainer checkout without installing the app, run:

```bash
make install-hooks
```

Existing custom Git hooks are preserved; installation stops if a different hooks
path is configured. Integrate the privacy checks manually in that case. The
ignored `.privacy-local.json` file can hold additional private identity terms.

No Codex skill is needed for these protections. `.gitignore` is part of every
clone, GitHub CI runs automatically, and this repository's AGENTS.md tells coding
agents to perform the privacy checks on every update. Git does not automatically
activate downloaded hooks on clone; setup or `make install-hooks` activates them
once per checkout. Confirm `git config --get core.hooksPath` reports `.githooks`
before publishing from another machine.

The public repository also has secret scanning and secret push protection
enabled. `main` requires passing **Privacy checks** and **macOS regression tests**
from GitHub Actions; the rules apply to administrators too. Force pushes and
branch deletion are disabled, and history must remain linear. Keep these
protections enabled and let the validated fast-forward route below satisfy them.

## Publish an update

1. Check the branch, upstream, working tree, and latest remote state. Fast-forward
   only a clean branch tracking its own upstream; preserve local edits.
2. Make the authorized change using synthetic examples and relative or dynamically
   resolved paths. Never copy app preferences, recordings, certificates, caches,
   private agent configuration, or a personal environment into source.
3. Run `make privacy`, `make test`, and `make build` as appropriate. Review the diff.
4. Stage the intended files individually and inspect `git diff --cached`.
5. Commit with the project identity, scoped to this command:

```bash
./scripts/commit.sh -m "Describe the change"
```

6. Run `python3 -B scripts/privacy_check.py --history --ref HEAD`, then push the
   intended branch. The installed push hook checks every outgoing ancestor too.
7. Verify GitHub Actions passed and the published diff contains only the intended
   public files. Require the privacy check through repository rules when available.

For a reviewed PR whose current head passes CI, preserve the neutral commit
identities when landing it. If the freshly fetched `main` is an ancestor of the
validated PR head, fast-forward `main` locally and push it normally. If integration
is required, create and validate the integration commit with the project identity
before landing. GitHub-generated merge, squash, and rebase commits can introduce
account attribution into commit metadata and will fail the history identity rule.
Do not bypass that rule or the installed hooks.

PR CI checks the combined test-merge files and runs macOS regressions against
that combined version. The history identity check examines the actual PR head,
excluding GitHub's temporary test-merge identity, which is not a release commit.

The commit wrapper leaves your global and shared Git settings unchanged. The
project identity is `Press To Write Maintainers <maintainers@presstowrite.invalid>`.
GitHub still records the account performing pushes and owning the repository.

Do not use `git push --mirror`, force-add ignored files, bypass the privacy hooks,
or merge an old clone's history into the cleaned repository during normal updates.
Build artifacts stay local; this source-sharing process does not publish compiled
apps, signing certificates, or dependency/model archives.
