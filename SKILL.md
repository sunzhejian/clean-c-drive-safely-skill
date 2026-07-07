---
name: clean-c-drive-safely
description: Safely audit and free Windows C drive space by classifying large directories, moving cache/application data to D or E with junctions, cleaning low-risk temporary files, and validating affected software. Use when the user asks to clean C drive, move caches off C, migrate WSL/Docker/Arduino/Python/user app data away from C, preserve application compatibility after cleanup, or reach a target free-space threshold without unsafe deletion.
---

# Clean C Drive Safely

## Overview

Free C drive space with a conservative, auditable workflow: inspect first, migrate with junctions when safe, delete only clearly disposable data, and verify the software that might have been affected.

## Workflow

1. Capture the target free-space goal and current disk state with `Get-PSDrive`.
2. Run a read-only audit before changing files:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit-c-drive.ps1 -Drive C -Top 80
```

3. Classify candidates into:
   - Safe to delete: old temp files, crash dumps, recycle bin when user explicitly allows it, screenshots when user explicitly allows it, stale build/cache files.
   - Safer to migrate: application caches, package caches, browser/dev-tool caches, user-level tool data.
   - Special handling: WSL distributions, Docker Desktop data, Arduino data/cache, Python PATH, package managers.
   - Do not touch without explicit instruction: `.codex`, documents/projects, source repositories, system folders, active databases, and unknown app data.
4. For migration, do a dry run first, then execute only selected paths:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/migrate-to-cache-volume.ps1 `
  -DestinationRoot E:\DevCaches\MigratedC `
  -SourcePaths C:\Users\me\AppData\Local\SomeCache `
  -LogDir E:\DevCaches\MigrationLogs

powershell -ExecutionPolicy Bypass -File scripts/migrate-to-cache-volume.ps1 `
  -DestinationRoot E:\DevCaches\MigratedC `
  -SourcePaths C:\Users\me\AppData\Local\SomeCache `
  -LogDir E:\DevCaches\MigrationLogs `
  -Execute
```

5. Validate every moved path and the important apps:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-cleanup.ps1 `
  -MigrationLog E:\DevCaches\MigrationLogs\c-drive-migration_YYYYMMDD_HHMMSS.csv `
  -TargetFreeGB 100
```

## Hard Rules

- Default to read-only scans until the candidate list is understood.
- Never move or delete `.codex` unless the user explicitly names it and confirms the risk.
- Never recursively delete or move a computed path unless its resolved absolute source and destination have been printed and verified to be inside the intended roots.
- Do not follow junctions/reparse points while measuring or deleting; otherwise a C cleanup can accidentally touch data already migrated to D or E.
- Skip a directory if a running process executable path is inside it.
- Prefer migration plus a junction over deletion for application data. Preserve the original C path for compatibility.
- Keep logs of migrated and deleted items outside C, for example `E:\DevCaches\MigrationLogs`.
- After changing PATH, distinguish registry/user PATH from the current process PATH. Refresh the process environment for validation when needed.
- If an operation requires administrator privileges and the current shell is not elevated, report that limitation instead of forcing it.

## Special Cases

- Docker Desktop: keep Docker WSL data together. Validate with `docker info`, `docker ps`, and `wsl -l -v`. Do not move `Program Files\Docker` without explicit instruction.
- WSL: verify distro base paths in `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss`; export/import only when a real move is needed. Test `wsl -d <name> --exec sh -lc "whoami; pwd"`.
- Arduino: keep Arduino body, data, downloads, and CLI cache on the intended non-C drive. Validate `arduino-cli version`, `arduino-cli core list`, and a small compile.
- Python: global `python` should normally point to the general Python install, not a project virtual environment. Project venvs should be invoked explicitly or activated per project.
- Browser and editor caches: close the app when possible. If not possible, migrate only inactive subdirectories or skip.

## References

Read `references/windows-cleanup-policy.md` before deleting anything beyond temporary files, screenshots explicitly allowed by the user, or crash dumps.

## Scripts

- `scripts/audit-c-drive.ps1`: read-only inventory for large root/user/app-data directories and known cleanup candidates.
- `scripts/migrate-to-cache-volume.ps1`: dry-run-by-default migration helper that moves selected C paths under a non-C root and creates junctions.
- `scripts/validate-cleanup.ps1`: verifies migration logs, free-space target, and common tools after cleanup.
