# Todo

## 2026-10-01 v8 Config Health-Check Fix

- [x] Sync the updater back to the running v8-era version (single `cli-proxy-api` service, paired `config.yaml`/compose backup, paired `--rollback`, v8 layout check, business API check). Verify: `sh -n` passes; live `--verify` on the router passes all checks.
- [x] Fix `check_api_models` awk to match any indentation (`[[:space:]]+`) instead of hardcoded 4/8 spaces, and reset `in_keys` when the `access:` block ends so later list items cannot be mistaken for keys. Verify: unit cases for 2/4-space layout, 4/8-space layout, quoted keys, and post-block list items all extract the correct key.
- [x] Refresh English and Chinese READMEs to the single-service behavior (drop CPA Manager Plus rows/variables, describe the v8 verify checks, pair backups and rollback). Verify: docs match implemented flags and defaults.

Review:
- The bug made `--verify` print "无法读取 access.api-keys" and silently skip the authenticated `/v1/models` check; the service itself was unaffected.
- The updater intentionally manages only the `cli-proxy-api` service; CPA Usage Keeper is updated separately.

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
