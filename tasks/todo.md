# Todo

## 2026-06-30 CPA Stack Smart Update Cleanup

- [x] Add safe cleanup of replaced Docker images after successful service updates. Verify: shell syntax check and script dry paths still parse.
- [x] Fix standalone `--verify` mode so it can run before version checks. Verify: `sh update-cpa-stack.sh --verify` reaches verification logic.
- [x] Document the cleanup behavior in English and Chinese READMEs. Verify: docs match implementation scope.

Review:
- Added targeted cleanup for the old image ID captured before each successful service update.
- Moved standalone `--verify` handling after `do_verify` is defined.
- Updated English and Chinese docs to describe old-image cleanup scope.

## 2026-06-30 CPA Stack Smart Update Final Hardening

- [x] Add a cleanup-only mode and dangling-image fallback. Verify: simulated update and cleanup-only paths call only image cleanup commands.
- [x] Remove the stray generated fragment file from the local repo. Verify: git status has no unrelated generated fragment.
- [x] Push the updated script and docs to GitHub. Verify: commit is on origin/main.

Review:
- Added `--cleanup-only` for safe dangling-image cleanup without service updates.
- Added post-update dangling-image cleanup after targeted old-image removal.
- Removed the stray generated fragment file from the working tree.
- Pushed commit `c108c2c` to `origin/main`.
