# Windows System Drive Cleanup Policy

## Risk Classes

Classify every candidate before mutation:

1. Disposable files: temp files, cache files, crash dumps, logs, old installers, screenshots, and recycle bin contents. Delete only when the category or file pattern is explicitly approved by the user or clearly requested.
2. Migratable state: package caches, browser/editor caches, package-manager stores, model caches, build caches, game launcher caches, and app data that can keep its original path through a junction.
3. Special handling: WSL distributions, Docker/Podman/VM data, databases, package managers, Python/Node/Rust/Java toolchains, Arduino/embedded toolchains, and applications with services or background agents.
4. Protected data: credentials, SSH keys, browser profiles with active sessions, password stores, documents, downloads not explicitly selected, source repositories, current project directories, agent/tool state, cloud sync roots, and unknown app data.

## Required Checks Before Mutation

- Print free space for all fixed drives, not only C/D/E.
- Print absolute source and destination paths.
- Resolve and verify the source is under the intended system drive.
- Resolve and verify the destination is under the chosen non-system destination root.
- Check whether the source is a reparse point. Skip reparse points by default.
- Check running process executable paths. Skip a directory when an active executable lives under it.
- Perform migration as move plus junction, not copy plus delete, unless a tool-specific export/import is required.
- Keep logs of migration and deletion actions on a non-system drive.

## Deletion Rules

Use deletion for files, not app directories. Prefer `remove-approved-files.ps1` because it is dry-run by default, logs every candidate, and refuses protected paths.

Allowed examples after review:

- `*.dmp`, `*.hprof`, `*.log`, `*.etl` in known diagnostic or temp locations.
- Screenshots or screen recordings only when the user explicitly allows screenshots to be removed.
- Old files in user temp, Windows temp, browser cache, or build cache roots.

Avoid deletion when:

- The file is inside a source repository, documents folder, credential folder, cloud sync root, or active app profile.
- The file extension is broad and ambiguous, such as `*.zip` or `*.db`, without user confirmation.
- The directory belongs to a database, VM, WSL distribution, Docker image store, or package manager.

## Migration Rules

Prefer migration for application data that the app expects to find at an existing path. A junction preserves compatibility for most Windows applications.

Do not migrate:

- The current agent state, unless the user intentionally asks and accepts interruption.
- A running app directory.
- A system-owned directory that requires admin rights unless the user explicitly wants an elevated operation.
- A path whose destination already exists, unless the user asks for a merge plan.

## Validation Rules

Validation must match what changed:

- Path migration: source path is a reparse point, destination exists, and the source resolves to the destination.
- CLI/tool migration: version command still works and package/cache path points to the intended volume when applicable.
- Daemon/service migration: process starts, health check passes, and logs do not show path errors.
- VM/container/WSL migration: runtime starts, distro/engine runs, and stored data is on the intended volume.
- PATH changes: a fresh process resolves commands in the expected order.
