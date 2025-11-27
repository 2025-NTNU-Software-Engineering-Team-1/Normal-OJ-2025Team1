# Static Analysis Failure Flow

```mermaid
sequenceDiagram
    participant User
    participant Frontend as Frontend (submit.vue)
    participant BackendAPI as Backend API (app.py)
    participant BackendModel as Backend Model (submission.py)
    participant SandboxAPI as Sandbox API (app.py)
    participant Dispatcher as Sandbox Dispatcher (dispatcher.py)
    participant StaticAnalyzer as Static Analyzer (static_analysis.py)

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
    
    Note over Dispatcher: Detects submissionMode!="ZIP"<br/>Starts Static Analysis

    Dispatcher->>Dispatcher: fetch_problem_rules(problem_id)
    
    alt Rules Exist
        Dispatcher->>StaticAnalyzer: analyze(submission_id, language, rules)
        StaticAnalyzer-->>Dispatcher: AnalysisResult (Success=False)
        
        Note over Dispatcher: Static Analysis Failed
        
        Dispatcher->>Dispatcher: _finalize_sa_failure(msg)
        Dispatcher->>Dispatcher: on_submission_complete()
        Dispatcher->>BackendAPI: PUT /submission/{id}/complete
        
        Note right of BackendAPI: Task Status = CE<br/>Stderr = "Static Analysis Not Passed: ..."
        
        BackendAPI->>BackendModel: on_submission_complete()
        BackendModel->>BackendModel: process_result()
        BackendModel->>BackendModel: finish_judging()
    else No Rules
        Dispatcher->>Dispatcher: Skip Analysis (Proceed to Build/Run)
    end
```

## Key Steps for Failure
1.  **Dispatcher**: Checks if `submissionMode` is NOT ZIP.
2.  **Dispatcher**: Fetches problem rules.
3.  **StaticAnalyzer**: Runs analysis. If it returns `is_success() == False`:
    *   **Dispatcher**: Logs warning.
    *   **Dispatcher**: Calls `_finalize_sa_failure`.
    *   **Result Construction**: Creates a result with `status="CE"` and `stderr` containing the failure message.
    *   **Early Return**: Skips build and execution queues.
    *   **Completion**: Immediately calls `on_submission_complete` to report back to Backend.
