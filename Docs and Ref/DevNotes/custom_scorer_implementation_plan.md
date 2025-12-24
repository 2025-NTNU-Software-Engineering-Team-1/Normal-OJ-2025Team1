# Custom Scorer Implementation Plan

## Goal
Implement Custom Scorer functionality to allow flexible scoring logic (e.g., partial credit, late penalties) using a user-provided Python script (`score.py`). This involves updating the Sandbox (Dispatcher, Runner), Backend (API, Submission processing), and standardizing naming conventions.

## User Review Required
> [!IMPORTANT]
> **Late Seconds API vs Metadata**: The plan proposes a new API (`GET /submission/<id>/late-seconds`) called by the Dispatcher at runtime.
> - **Pros**: Decouples submission transfer from deadline logic; allows dynamic updates if deadlines change.
> - **Cons**: Adds a runtime dependency on the Backend during judging.
> - **Alternative**: Include `lateSeconds` in the initial `meta.json` payload.
> - **Decision**: Proceed with **New API**;若題目無作業資訊則回傳 `-1` 表示跳過。

> [!NOTE]
> **Scorer Artifacts**: `checkerArtifacts` (e.g., Interactive Mode's `Check_Result`) must be accessible to the Scorer container.
> - **Strategy**: Ensure these artifacts are copied to the Scorer's working directory (`/workspace`) before execution.

## Proposed Changes

### 1. Naming & Infrastructure Standardization
Rename `custom_checker` resources to `noj-custom-checker-scorer` to reflect shared usage.
#### [MODIFY] Sandbox Configuration & Scripts
- `Sandbox/build.sh`: Update image tag.
- `Sandbox/custom_checker_scorer_dockerfile`: Build tag `noj-custom-checker-scorer`.
- `Sandbox/.config/submission.json`: Update default image name.
- `README.md`, `changelog`: Update references.

### 2. Meta & Config Support
Support `scoringScript` in problem configuration.
#### [MODIFY] Sandbox/dispatcher
- `dispatcher/meta.py`: Add `scoringScript` (bool) and `checkerAsset` / `scorerAsset` fields to `Meta` class.
- `dispatcher/testdata.py`: Update `get_problem_meta` to parse new fields.

### 3. Backend: Late Info API
Expose submission lateness information.
#### [MODIFY] Back-End/mongo
- `mongo/submission.py` or `mongo/problem.py`: Add logic to calculate late seconds based on submission time and homework deadline.
- `problem_api` or `submission_api`: Add endpoint `GET /submission/<id>/late-seconds`.

### 4. Sandbox: Scorer Preparation
Download and cache scoring scripts（僅 `score.py`，不支援 `score.json`）。
#### [NEW] Sandbox/dispatcher/custom_scorer.py
- Implement `ensure_custom_scorer`: Download `score.py` from Backend.
- Implement `run_custom_scorer`: Orchestrate the scorer execution.

### 5. Sandbox: Scorer Execution
Execute the scoring script in a container.
#### [NEW] Sandbox/runner
- 新增 `runner/custom_scorer_runner.py`（與 custom checker runner 分開），執行 `score.py`：stdin 傳 JSON、stdout 讀 JSON。

#### [MODIFY] Sandbox/dispatcher/dispatcher.py
- `handle`: Update workflow to include Scorer step（無 custom scorer 時沿用預設計分）。
- `on_submission_complete`:
    - Call `late-seconds` API.
    - Construct Scoring Input JSON (tasks, stats, artifacts).
    - Run Scorer.
    - Parse output.
    - Update result payload with `score`, `message`, `breakdown`.

### 6. Backend: Result Processing
Handle scoring results.
#### [MODIFY] Back-End/mongo/submission.py
- `process_result`:
    - Accept `score`, `message`, `breakdown` from Sandbox.
    - Update `submission.score` (total score).
    - If Scorer fails (JE), set `submission.status = JE` (preserve task statuses).

## Verification Plan

### Automated Tests
- **Sandbox Tests**:
    - `tests/test_dispatcher.py`:
        - Test Scorer AC (normal scoring).
        - Test Scorer Partial Credit.
        - Test Scorer Crash/Timeout -> JE.
        - Test Missing Asset -> JE.
    - `tests/test_custom_scorer.py` (New): Unit tests for `custom_scorer.py`.
- **Backend Tests**:
    - `tests/test_submission.py`: Verify `process_result` handles scoring fields correctly.

### Manual Verification
1.  **Build**: Run `build.sh` to verify image renaming.
2.  **Deploy**: Deploy updated Sandbox and Backend.
3.  **Test Case 1: Normal Scoring**: Submit a problem with `score.py`. Verify score and message.
4.  **Test Case 2: Late Submission**: Submit late (mock deadline). Verify `lateSeconds` is passed and penalty applied.
5.  **Test Case 3: Interactive Mode**: Submit interactive problem. Verify Scorer receives `Check_Result`.
6.  **Test Case 4: Scorer Error**: Upload broken `score.py`. Verify Submission Status is JE.
