# Application Validation Playbook

Use this playbook to choose validation checks after cleanup. Do not assume the target machine has the same software as any previous cleanup.

## Discover

- Identify running processes and executable paths.
- Inspect user and machine PATH entries.
- Find app-specific config for cache/data paths before moving anything.
- Prefer official export/import tools for VM, WSL, database, and container data.

## Common App Classes

### CLI tools and language runtimes

Examples: Python, Node.js, Rust, Java, Go, Git, package managers.

Validate with version commands, package-cache commands, and a small smoke command. Check both the persistent PATH and current process PATH.

### Developer tools and editors

Examples: VS Code, JetBrains IDEs, Cursor-like editors, embedded IDEs.

Validate the executable starts or reports a version. Treat extensions, global storage, and caches separately. Do not delete workspace data.

### Browsers and webviews

Migrate only caches when the browser is closed. Avoid moving active profile roots unless the user understands session risk. Validate launch and profile availability.

### Container, VM, and WSL runtimes

Examples: Docker Desktop, Podman, Hyper-V VMs, VMware/VirtualBox, WSL distros.

Prefer official export/import or settings-based moves. Validate engine status, image/container listing, and at least one distro or VM boot.

### Databases and local services

Examples: PostgreSQL, MySQL, Redis, Elasticsearch, vector stores.

Stop services gracefully before moving data. Validate service status, socket/port availability, and a simple query or health check.

### Creative, CAD, game, and launcher apps

Treat media libraries and projects as protected by default. Caches may be large but app-specific. Validate launch and a recent-project list only if the user approves interacting with the app.

## Reporting

Report:

- Final free space.
- What was migrated, deleted, skipped, or blocked.
- Which checks passed.
- Which apps could not be verified and why.
