# Press To Write repository instructions

## Privacy is required for every update

This repository is intended for public source sharing. Keep personal names,
email addresses, account handles, machine paths, dictated text, recordings,
preferences, credentials, signing material, and private agent configuration out
of source, examples, screenshots, commit messages, and commit identities.
Use synthetic examples and paths resolved on the recipient's own machine.

Before editing, inspect branch, upstream, local changes, and remote freshness.
Preserve unrelated edits and shared settings. Before committing or pushing:

1. Run `make install-hooks` if this checkout has not been prepared. Do not replace
   existing custom hooks; integrate the privacy checks without losing them.
2. Run `make privacy` and review the complete intended diff. Automated checks
   cannot recognize every form of personal information.
3. Stage only named, reviewed public files. Run
   `python3 -B scripts/privacy_check.py --staged` against the actual index.
4. Commit with `./scripts/commit.sh` to keep the project identity scoped to the
   command. Do not change shared or global Git identity settings.
5. Run `python3 -B scripts/privacy_check.py --history --ref HEAD` before pushing,
   and let the installed commit and push hooks finish.
6. Wait for current-head GitHub privacy and macOS checks before landing an update.
   Preserve neutral commit identities using the route in MAINTAINING.md.

Never bypass privacy checks, force-add private/generated files, push local
preservation refs, use `git push --mirror`, or merge history from a pre-cleanup
clone. Do not weaken privacy rules merely to obtain a passing result. Remediate
private content before publication; rotate exposed credentials if necessary.

Owner-specific deny terms belong only in the ignored `.privacy-local.json`.
Keep app preferences, recordings, runtime environments, model weights, and
private backups outside published files. No API keys are needed for dictation.

## Release and license

The official release is the GitHub source on `main`. Follow MAINTAINING.md and
update PROGRESS.md with accurate validation and handoff status. There is no
website deployment or compiled-app distribution pipeline to invent.

The Unmodified Use License permits running official versions and configuration
through the app. Source modification and redistribution require the copyright
holder's permission. Third-party dependencies retain their own licenses.
