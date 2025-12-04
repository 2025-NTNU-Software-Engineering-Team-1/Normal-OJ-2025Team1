# Custom Scorer Flow

```mermaid
sequenceDiagram
    participant User
    participant Frontend as Frontend (submit.vue)
    participant BackendAPI as Backend API (app.py)
    participant BackendModel as Backend Model (submission.py)
    participant SandboxAPI as Sandbox API (app.py)
    participant Dispatcher as Sandbox Dispatcher (dispatcher.py)
    participant CustomScorer as Custom Scorer (custom_scorer.py)
    participant ScorerRunner as Scorer Runner (custom_scorer_runner.py)

    User->>Frontend: Upload Code (File)
    Frontend->>Frontend: Validate Format
    Frontend->>BackendAPI: POST /submission/ (create_submission)
    BackendAPI->>BackendModel: Submission.add()
    BackendModel-->>BackendAPI: submission_id
    BackendAPI-->>Frontend: submission_id

    Frontend->>BackendAPI: PUT /submission/{id} (update_submission)
    BackendAPI->>BackendModel: submission.submit(code)
    BackendModel->>BackendModel: _put_code(code) (Upload to MinIO)
    BackendModel->>BackendModel: send()
    BackendModel->>SandboxAPI: POST /submit/{id}

    SandboxAPI->>Dispatcher: prepare_submission_dir()
    Dispatcher->>Dispatcher: file_manager.extract()
    SandboxAPI->>Dispatcher: handle(submission_id)
    Dispatcher->>Dispatcher: get_problem_meta()
    
    Note over Dispatcher: Checks meta.scoringScript<br/>Prepares Custom Scorer

    Dispatcher->>Dispatcher: _prepare_custom_scorer()
    Dispatcher->>CustomScorer: ensure_custom_scorer(problem_id)
    CustomScorer->>BackendAPI: GET /problem/{id}/asset/scoring_script
    BackendAPI-->>CustomScorer: score.py (binary)
    CustomScorer->>CustomScorer: Cache to testdata/{id}/custom_scorer/
    CustomScorer->>CustomScorer: Copy to submissions/{id}/scorer/
    CustomScorer-->>Dispatcher: scorer_path
    Dispatcher->>Dispatcher: Store custom_scorer_info

    Note over Dispatcher: Build & Execute Test Cases<br/>(Normal Flow)

    Dispatcher->>Dispatcher: compile() / create_container()
    Dispatcher->>Dispatcher: on_case_complete() × N
    Dispatcher->>Dispatcher: on_submission_complete()

    Note over Dispatcher: All Cases Complete<br/>Run Custom Scorer

    Dispatcher->>Dispatcher: _run_custom_scorer_if_needed()
    
    Dispatcher->>BackendAPI: GET /submission/{id}/late-seconds
    BackendAPI->>BackendModel: submission.calculate_late_seconds()
    BackendModel->>BackendModel: Check homework deadlines
    BackendModel-->>BackendAPI: lateSeconds
    BackendAPI-->>Dispatcher: {"lateSeconds": 86400}

    Dispatcher->>Dispatcher: _build_scoring_tasks(results)
    Dispatcher->>Dispatcher: _build_scoring_stats(results)
    
    Note over Dispatcher: Construct Scorer Input JSON
    
    Dispatcher->>CustomScorer: run_custom_scorer(scorer_path, payload)
    CustomScorer->>CustomScorer: Create workdir/score.py
    CustomScorer->>CustomScorer: PathTranslator.to_host(workdir)
    CustomScorer->>ScorerRunner: CustomScorerRunner.run(payload)
    
    Note over ScorerRunner: Write scoring_input.json<br/>(⚠️ PATH BUG: uses host path)
    
    ScorerRunner->>ScorerRunner: docker.create_container()
    ScorerRunner->>ScorerRunner: Bind mount workdir
    ScorerRunner->>ScorerRunner: Execute: python3 score.py < input.json
    ScorerRunner->>ScorerRunner: Wait for completion
    ScorerRunner->>ScorerRunner: Collect stdout/stderr
    ScorerRunner-->>CustomScorer: {"exit_code": 0, "stdout": "...", "stderr": ""}
    
    CustomScorer->>CustomScorer: _parse_scorer_output(result)
    CustomScorer->>CustomScorer: json.loads(stdout)
    CustomScorer-->>Dispatcher: {"status": "OK", "score": 85, "message": "...", "breakdown": {...}}

    Dispatcher->>Dispatcher: Construct submission_data
    Dispatcher->>BackendAPI: PUT /submission/{id}/complete
    
    Note right of BackendAPI: Includes:<br/>- tasks (case results)<br/>- scoring (score, message, breakdown)<br/>- statusOverride (if JE)

    BackendAPI->>BackendModel: on_submission_complete()
    BackendModel->>BackendModel: process_result(scoring=...)
    
    alt Scorer Provided Score
        BackendModel->>BackendModel: Override total score
        BackendModel->>BackendModel: Update scoring_message
        BackendModel->>BackendModel: Store scoring_breakdown
        BackendModel->>BackendModel: Upload scorer artifacts to MinIO
    else Scorer Failed (JE)
        BackendModel->>BackendModel: Set status to JE
        BackendModel->>BackendModel: Store error in scoring_message
    end
    
    BackendModel->>BackendModel: finish_judging()
    BackendModel-->>BackendAPI: Success
    BackendAPI-->>SandboxAPI: 200 OK
```

## Key Steps for Custom Scorer

### 1. Preparation Phase (Dispatcher)
- **Trigger**: `meta.scoringScript == true` detected during `handle()`
- **Action**: Call `_prepare_custom_scorer()`
  - Fetch `scoring_script` asset from Backend
  - Cache to `testdata/{problem_id}/custom_scorer/score.py`
  - Copy to `submissions/{submission_id}/scorer/score.py`
  - Store `scorer_path` in `custom_scorer_info`

### 2. Execution Phase (Normal Flow)
- Build submission (if needed)
- Execute all test cases
- Collect results in `self.result[submission_id]`

### 3. Scoring Phase (After All Cases Complete)
- **Trigger**: `on_submission_complete()` detects `custom_scorer_info[submission_id]["enabled"] == true`
- **Action**: Call `_run_custom_scorer_if_needed()`

#### 3.1 Fetch Late Penalty
- Call Backend API: `GET /submission/{id}/late-seconds?token=...`
- Backend calculates `lateSeconds` based on homework deadlines
- Returns `-1` if no homework or not late

#### 3.2 Build Scorer Input
- `_build_scoring_tasks()`: Convert case results to scorer format
  ```json
  {
    "tasks": [[{"status": "AC", "execTime": 123, "memoryUsage": 1024}, ...]],
    "stats": {"maxRunTime": 500, "avgRunTime": 250, ...},
    "lateSeconds": 0,
    "staticAnalysis": {...},
    "checker": {...}
  }
  ```

#### 3.3 Execute Scorer
- `custom_scorer.run_custom_scorer()`:
  - Create `workdir` (WSL path)
  - Copy `score.py` to workdir
  - **⚠️ BUG**: Translate workdir to host path, pass to runner
  - Runner writes `scoring_input.json` using host path ❌ (fails in WSL)
  - Launch Docker container with Python
  - Container reads JSON from stdin, executes `score.py`
  - Collect stdout (JSON result) and stderr

#### 3.4 Parse Result
- `_parse_scorer_output()`: Parse JSON from stdout
  ```json
  {
    "score": 85,
    "message": "Task 1: 2/2 → 30 pts | Time Bonus: +5 pts",
    "breakdown": {"taskScores": [30, 40, 15], "timeBonus": 5}
  }
  ```
- If exit_code != 0 or JSON invalid: Return JE

### 4. Reporting Phase
- Construct `scoring` payload for Backend
- Include `score`, `message`, `breakdown`, `artifacts` (stdout/stderr)
- Send to Backend: `PUT /submission/{id}/complete`

### 5. Backend Processing
- `BackendModel.process_result(scoring=...)`:
  - Override `self.score` with `scoring["score"]`
  - Store `scoring_message` and `scoring_breakdown`
  - Upload scorer artifacts (stdout/stderr) to MinIO
  - If `scoring_status == "JE"`: Override submission status

## Data/Field Mapping

### Sandbox ➜ Backend
**Payload**: `PUT /submission/{id}/complete`
```json
{
  "tasks": [...],
  "scoring": {
    "status": "OK" | "JE",
    "score": 85,
    "message": "Partial credit: ...",
    "breakdown": {"taskScores": [30, 40, 15]},
    "artifacts": {"stdout": "...", "stderr": "..."}
  },
  "statusOverride": "JE"  // if scorer failed
}
```

### Backend Storage
- `score`: Overridden by `scoring.score`
- `scoring_message`: Scorer's message
- `scoring_breakdown`: JSON dict of score details
- `scorer_artifacts_path`: MinIO path to uploaded stdout/stderr

### Frontend Display
- Show custom score instead of default score
- Display `scoringMessage` in submission details
- Provide breakdown visualization (if available)



## Comparison with Custom Checker

| Feature | Custom Checker | Custom Scorer |
|---------|----------------|---------------|
| **Trigger** | `meta.customChecker == true` | `meta.scoringScript == true` |
| **Execution Timing** | Per-case (during execution) | After all cases complete |
| **Input** | Case-specific files (input.in, answer.out, student.out) | All case results + stats (JSON) |
| **Output** | STATUS + MESSAGE | score + message + breakdown (JSON) |
| **File Writing** | All files written before translation ✅ | `scoring_input.json` written after translation ❌ |
| **Backend Integration** | Updates case status | Overrides total score |
