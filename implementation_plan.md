# Fix Interactive Submission Pending Issue

## Problem Description
Submission `692b126d4763317bfb3143ef` is stuck in pending. The problem is interactive.
Logs show `strategy=COMPILE` is being used, which is incorrect for interactive problems (should be `MAKE_INTERACTIVE` to prepare teacher files).
The Backend defaults to `COMPILE` for interactive code submissions (non-zip), causing the Sandbox to skip teacher file preparation.
The Sandbox's `MAKE_INTERACTIVE` strategy currently enforces `Makefile` presence, which fails for code submissions.

## Proposed Changes

### Back-End

#### [MODIFY] [problem_utils.py](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Back-End/model/utils/problem_utils.py)
- Update `derive_build_strategy` to return `'makeInteractive'` for all interactive problems, regardless of submission mode (zip or code).

### Sandbox

#### [MODIFY] [build_strategy.py](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py)
- Update `prepare_make_interactive` to handle `SubmissionMode.CODE` (missing Makefile).
    - Check if `Makefile` exists in `src`. If not, return `BuildPlan(needs_make=False)`.
- Wrap logic in `prepare_make_interactive` and `prepare_interactive_compile` in `try...except Exception` blocks to catch unhandled errors (like network issues or missing assets) and raise `BuildStrategyError`. This prevents the Dispatcher thread from crashing.

## Verification Plan

### Automated Tests
- Create a unit test for `derive_build_strategy` in `Back-End` to verify it returns `'makeInteractive'` for interactive code submissions.
- Create a unit test for `prepare_make_interactive` in `Sandbox` to verify it returns `needs_make=False` for C/C++ code submissions without Makefile.
- Verify that `BuildStrategyError` is raised (instead of crash) when assets are missing.

### Manual Verification
- Ask the user to rejudge the stuck submission.
- Monitor `sandbox.log`.
    - Expect to see `strategy=MAKE_INTERACTIVE`.
    - If assets are missing, expect to see `WARNING:app:build strategy failed ...` instead of a silent crash/restart.
    - If assets are present, expect successful compilation and execution.
