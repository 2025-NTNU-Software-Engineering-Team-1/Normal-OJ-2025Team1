# Path Translation Architecture

## Overview

The Sandbox service uses a `PathTranslator` utility to handle file path conversions between the Sandbox container's internal view and the Docker host's view. This is crucial for correctly binding volumes when the Sandbox (Dispatcher) spawns sibling containers (Runners) via the Docker socket.

## Why Path Translation is Needed

### The "Container-in-Container" Pattern

The Sandbox Dispatcher runs inside a Docker container but spawns new containers (Runners) using the host's Docker daemon (via `/var/run/docker.sock`).

1.  **Dispatcher View**: The Dispatcher sees files at a path inside its container (e.g., `/app/submissions/...` or a mounted volume path).
2.  **Docker Daemon View**: The Docker daemon runs on the host and expects host filesystem paths for bind mounts.
3.  **The Mismatch**: If the Dispatcher tries to bind a path it sees (e.g., `/app/submissions/...`) to a new container, the Docker daemon will look for that path on the *host*. If the paths don't match, the bind mount fails or mounts the wrong directory.
4.  **New Structure**: With the introduction of `src/common` (build artifacts) and `src/cases/<case_no>` (execution context), the Dispatcher now manages these specific subdirectories. The `PathTranslator` handles these paths seamlessly as long as they are within the `sandbox_root`.

### Translation Logic

The `PathTranslator` converts paths using two configuration values:
*   `sandbox_root`: The root directory as seen by the Dispatcher (inside its container).
*   `host_root`: The corresponding root directory on the Docker host.

Logic:
```python
rel_path = path_inside_sandbox.relative_to(sandbox_root)
path_on_host = host_root / rel_path
```

## Current Architecture & Configuration

### Deployment Scenarios

#### 1. Development (Host Path Mapping)
In the current development environment, the `working_dir` is configured to be the absolute path on the host machine.

*   **Config**: `{"working_dir": "/home/user/.../Sandbox/submissions"}`
*   **Result**: `sandbox_root` defaults to the parent of `working_dir`, which is the host path. `host_root` defaults to `sandbox_root`.
*   **Effect**: `sandbox_root == host_root`. The translation is an **identity function** (no change).
*   **Why it works**: The Dispatcher uses the host path to access files (via shared mounts or network shares), and passes the same host path to Docker.

#### 2. Production (Container Path Mapping)
In a standard production deployment, the Dispatcher might be configured with internal container paths.

*   **Config**:
    ```json
    {
      "working_dir": "/app/submissions",
      "sandbox_root": "/app",
      "host_root": "/opt/noj/Sandbox"
    }
    ```
*   **Effect**: `sandbox_root (/app) != host_root (/opt/noj/Sandbox)`.
*   **Why it works**: The Dispatcher works with `/app/...`. When spawning a runner, it translates `/app/submissions/123` to `/opt/noj/Sandbox/submissions/123`, which the Docker daemon correctly binds.

## Implementation

The logic is centralized in `Sandbox/runner/path_utils.py`.

```python
class PathTranslator:
    def to_host(self, path: str | Path) -> Path:
        # ... logic to convert path ...
```

This utility is used by:
*   `InteractiveRunner` (`Sandbox/runner/interactive_runner.py`)
*   `SubmissionRunner` (`Sandbox/runner/submission.py`)

## Decision Matrix for Configuration

| Environment | `working_dir` Config | `sandbox_root` | `host_root` | Translation Needed? |
| :--- | :--- | :--- | :--- | :--- |
| **Dev (Current)** | Host Path (e.g., `/home/...`) | Host Path | Host Path | No (Identity) |
| **Prod (Type A)** | Container Path (`/app/...`) | `/app` | Host Path | **Yes** |
| **Prod (Type B)** | Host Path (via Env Var) | Host Path | Host Path | No (Identity) |

**Recommendation**: Keep `PathTranslator` active. It handles the Identity case correctly (zero overhead) and provides flexibility for containerized deployments without code changes.
