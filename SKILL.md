---
name: clean-c-drive-safely
description: Mature Windows disk-space remediation workflow for safely auditing a full system drive, classifying risk, migrating cache or application data to another volume with junctions, deleting only explicitly approved disposable files, and validating affected software. Use when a user asks to clean C drive, free Windows system-drive space, move caches or app data off the system drive, migrate WSL/Docker/package-manager/developer-tool data, or preserve app compatibility after storage cleanup on any Windows PC.
---

# Clean C Drive Safely

## Overview

Use a conservative, repeatable workflow for Windows system-drive cleanup. Treat every machine as different: discover the user's drives, apps, active processes, and target free-space goal before changing anything.

## Operating Model

1. Establish scope:
   - Confirm the system drive, target free space, destination volume, and whether the user permits deletion or only migration.
   - Prefer a destination with enough free space and a simple root such as `X:\DevCaches` or `X:\AppDataOffload`.
2. Audit read-only first:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit-c-drive.ps1 `
  -SystemDrive C `
  -Top 80 `
  -OutputDir X:\CleanupLogs
```

3. Classify candidates with `references/windows-cleanup-policy.md`.
4. Migrate app data only after a dry run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/migrate-to-cache-volume.ps1 `
  -SourceDrive C `
  -DestinationRoot X:\AppDataOffload `
  -SourcePaths C:\Users\me\AppData\Local\ExampleCache `
  -LogDir X:\CleanupLogs
```

Run again with `-Execute` only after reviewing dry-run output.
5. Delete files only when the user explicitly approves the category or pattern:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/remove-approved-files.ps1 `
  -Roots C:\Users\me\Pictures,C:\Users\me\Downloads `
  -NamePatterns "*Screenshot*","*screen shot*","*snip*" `
  -Extensions .png,.jpg,.jpeg,.webp `
  -LogDir X:\CleanupLogs
```

Run again with `-Execute` only after reviewing the deletion log preview.
6. Validate the cleanup and affected software:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-cleanup.ps1 `
  -SystemDrive C `
  -TargetFreeGB 100 `
  -MigrationLog X:\CleanupLogs\drive-migration_YYYYMMDD_HHMMSS.csv `
  -Checks python,node,wsl,docker
```

## Hard Rules

- Start read-only. Do not mutate files until the largest space users and risks are understood.
- Do not follow junctions or reparse points while measuring, deleting, or selecting cleanup candidates.
- Never recursively delete application directories. Delete only approved files, and migrate app data with a junction when compatibility matters.
- Never move or delete tool state for the current agent, credentials, source repositories, documents, active databases, or unknown business data unless the user explicitly confirms that exact path.
- Skip migration when a running process executable path is inside the source path.
- Log every migration and deletion outside the system drive.
- If an operation needs administrator privileges, report the limitation and use non-admin alternatives first.
- After PATH or environment changes, distinguish persistent user/machine environment from the current process environment and refresh the process PATH before validation.

## References

- Read `references/windows-cleanup-policy.md` before deletion or migration.
- Read `references/application-validation-playbook.md` when cleanup touches developer tools, virtualized runtimes, package managers, browsers, creative tools, games, or databases.

## Scripts

- `scripts/audit-c-drive.ps1`: read-only inventory of drives, large directories, known disposable candidates, and running processes.
- `scripts/migrate-to-cache-volume.ps1`: dry-run-by-default migration helper that moves selected system-drive paths to another volume and creates junctions.
- `scripts/remove-approved-files.ps1`: dry-run-by-default file deletion helper for explicitly approved patterns such as screenshots, crash dumps, or stale temp files.
- `scripts/validate-cleanup.ps1`: validates free-space targets, migration logs, and selected app/tool checks.
