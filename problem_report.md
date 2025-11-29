# Interactive Problem Logic Review & Problem Report

## Overview
A comprehensive review of the interactive problem submission flow has revealed multiple critical issues causing submissions to get stuck or fail.

## Identified Issues

### 1. Backend Strategy Mismatch (Critical)
- **Location**: `Back-End/model/utils/problem_utils.py` (`derive_build_strategy`)
- **Issue**: For interactive problems with **Code** submission mode (not Zip), the Backend defaults to returning the `COMPILE` strategy.
- **Impact**: The `COMPILE` strategy in Sandbox only compiles the student's code. It **does not** compile the teacher's code.
- **Result**: The `InteractiveRunner` fails because it cannot find the teacher's binary (`Teacher_main`), or the Dispatcher crashes trying to find it.

### 2. Sandbox Build Strategy Flaw (Critical)
- **Location**: `Sandbox/dispatcher/build_strategy.py` (`prepare_make_interactive`)
- **Issue**: The `MAKE_INTERACTIVE` strategy strictly enforces the presence of a `Makefile`.
- **Impact**: **Code** submissions (which are single files like `main.c`) do not have a `Makefile`.
- **Result**: If we simply switch the Backend to send `MAKE_INTERACTIVE`, these submissions will still fail with "Makefile not found".

### 3. Dispatcher Instability (Critical)
- **Location**: `Sandbox/dispatcher/dispatcher.py` & `build_strategy.py`
- **Issue**: The `Dispatcher` thread does not properly catch exceptions raised during the build preparation phase (e.g., network errors when fetching assets, or `BuildStrategyError`).
- **Impact**: When an error occurs (like "teacher compile failed"), the exception propagates up and kills the `Dispatcher` thread. The service manager (Docker/Systemd) likely restarts the service, causing the submission to remain in "Pending" state indefinitely or until manual intervention.

### 4. Static Analysis False Positives (Minor)
- **Location**: `Sandbox/dispatcher/static_analysis.py`
- **Issue**: Static analysis for C/C++ fails if it cannot find `main.c` or `main.cpp`.
- **Impact**: For some submission types or if extraction fails, this raises an error. While not the root cause of the "stuck" submission, it adds noise to the logs.

## Proposed Solution (Implementation Plan)

1.  **Fix Backend**: Update `derive_build_strategy` to **always** return `makeInteractive` for interactive problems, regardless of submission mode.
2.  **Fix Sandbox**: Update `prepare_make_interactive` to handle Code submissions:
    - If no `Makefile` is found in `src`, assume it's a simple code submission.
    - Fallback to default compilation logic (compile `main.c` -> `main`) for the student code.
    - **Crucially**, still proceed to prepare and compile the teacher code.
3.  **Stabilize Dispatcher**: Wrap build strategy execution in `try-except` blocks to catch `BuildStrategyError` and other exceptions. Report these as "Compilation Error" (CE) or "System Error" (SE) instead of crashing.

## Next Steps
Proceed with the implementation of the above fixes as detailed in `implementation_plan.md`.
