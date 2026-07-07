# Windows C Drive Cleanup Policy

## Classification

Treat cleanup candidates as one of four classes:

1. Delete candidates: recycle bin with user approval, old temp files, crash dumps, installer logs, screenshots when the user explicitly says screenshots may be removed.
2. Migrate candidates: caches, package stores, browser/editor caches, user-level app data that must keep the same C path through a junction.
3. Special cases: WSL, Docker Desktop, Arduino, Python, package managers, databases, and virtual disks.
4. Protected data: `.codex`, documents, source repositories, current project data, credentials, SSH keys, browser profiles with active sessions, and unknown application data.

## Required Checks Before Mutation

- Print current free space for C, D, and E.
- Print the absolute source and destination path.
- Confirm the source is on C and the destination is under the chosen non-C root.
- Check whether the source is a reparse point; skip links by default.
- Check running process executable paths; skip directories that contain running executables.
- Prefer Move-Item plus junction for app data; use deletion only for clearly disposable data.
- Log every migration and deletion to a non-C directory.

## Validation

After cleanup, validate the exact software touched or likely affected. Common checks:

```powershell
Get-PSDrive C,D,E
docker info
docker ps
wsl --list --verbose
arduino-cli version
arduino-cli core list
python --version
python -m pip --version
node --version
npm config get cache
```

For project environments, run the repo's own verification script or build command. Report any app that cannot be verified.
