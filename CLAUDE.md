# GhostPin — instructions for Claude

## Workflow

- **Never commit or push directly to `main`.** Every change — bug fix, feature, docs, config — goes on its own branch and lands through a pull request, even for a single commit. The user reviews and merges PRs.
- One logical change per branch/PR. Stacked PRs are fine, but note the stack in the PR body, and remember GitHub only retargets a stacked PR to `main` if the base branch is deleted when its PR merges.

## Releasing

- Release assets must keep the stable names `GhostPin.dmg` and `GhostPin.dmg.sha256` in every release — all download links point at the permanent URL `releases/latest/download/GhostPin.dmg`.
- The app is ad-hoc signed: every rebuild changes the binary hash, which invalidates the user's Screen Recording grant. After a rebuild, `tccutil reset ScreenCapture com.aadhilfarhan.ghostpin` then relaunch for a clean permission prompt.
