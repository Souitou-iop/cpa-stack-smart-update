# Todo

## 2026-07-02 CPA Manager Plus Migration Support

- [x] Change the default manager image/repo from legacy CPA-Manager to CPA Manager Plus. Verify: shell syntax check and live `--check-only` on the router.
- [x] Keep the existing compose service name `cpa-manager` so migrated stacks update in place. Verify: script still inspects/recreates service `cpa-manager`.
- [x] Update verification to include the CPAMP `/health` endpoint. Verify: live `--verify` reaches CLIProxyAPI and CPAMP endpoints.
- [x] Update English and Chinese README defaults and migration notes. Verify: docs mention admin key and `/data/data.key` backup requirements.

Review:
- Default manager updates now target `seakee/cpa-manager-plus:latest` and `seakee/CPA-Manager-Plus` releases.
- The updater intentionally keeps the service/container name `cpa-manager` to match migrated compose files.
- Documentation now reflects CPA Manager Plus credentials and data key handling.

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
