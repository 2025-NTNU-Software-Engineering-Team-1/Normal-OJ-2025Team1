# ZIP Mode Submission Flow

```mermaid
sequenceDiagram
    participant User
    participant Frontend as Frontend (submit.vue)
    participant BackendAPI as Backend API (app.py)
    participant BackendModel as Backend Model (submission.py)
    participant SandboxAPI as Sandbox API (app.py)
    participant Dispatcher as Sandbox Dispatcher (dispatcher.py)
    participant BuildStrategy as Build Strategy (build_strategy.py)
    participant Runner as Submission Runner (runner/submission.py)

    User->>Frontend: Upload ZIP File
    Frontend->>Frontend: Validate Format (acceptedFormat="zip")
    Frontend->>BackendAPI: POST /submission/ (create_submission)
    BackendAPI->>BackendModel: Submission.add()
    BackendModel-->>BackendAPI: submission_id
    BackendAPI-->>Frontend: submission_id

    Frontend->>BackendAPI: PUT /submission/{id} (update_submission)
    BackendAPI->>BackendModel: submission.submit(zip_file)
    BackendModel->>BackendModel: _put_code(zip_file) (Upload to MinIO)
    BackendModel->>BackendModel: send()
    BackendModel->>SandboxAPI: POST /submit/{id}

    SandboxAPI->>Dispatcher: prepare_submission_dir()
    Dispatcher->>Dispatcher: file_manager.extract()
    SandboxAPI->>Dispatcher: handle(submission_id)
    Dispatcher->>Dispatcher: get_problem_meta()
    
    Note over Dispatcher: Detects submissionMode="ZIP"<br/>Skips Static Analysis

    Dispatcher->>Dispatcher: _prepare_with_build_strategy()
    
    alt buildStrategy="makeNormal" (Typical for ZIP)
        Dispatcher->>BuildStrategy: prepare_make_normal()
        BuildStrategy-->>Dispatcher: BuildPlan (needs_make=True)
    else buildStrategy="compile"
        Dispatcher->>BuildStrategy: BuildPlan (needs_make=False)
    end

    opt needs_make=True
        Dispatcher->>Dispatcher: queue.put(job.Build)
    end
    Dispatcher->>Dispatcher: queue.put(job.Execute)

    loop Dispatcher Run Loop
        Dispatcher->>Dispatcher: job = queue.get()
        
        alt job.Build
            Dispatcher->>Dispatcher: build()
            Dispatcher->>Runner: build_with_make()
            Runner-->>Dispatcher: Result (AC/CE)
        else job.Execute
            Dispatcher->>Dispatcher: create_container()
            Dispatcher->>Runner: run()
            Runner-->>Dispatcher: Result (Output/Status)
            Dispatcher->>Dispatcher: on_case_complete()
        end
    end

    Dispatcher->>Dispatcher: on_submission_complete()
    Dispatcher->>BackendAPI: PUT /submission/{id}/complete
    BackendAPI->>BackendModel: on_submission_complete()
    BackendModel->>BackendModel: process_result()
    BackendModel->>BackendModel: finish_judging()
```

## Key Differences from Function Only
1.  **Frontend**: Validates `acceptedFormat="zip"`.
2.  **Sandbox**:
    *   **Skips Static Analysis**: `is_zip_mode` is True.
    *   **Build Strategy**: Typically uses `makeNormal` (expects a `Makefile` in the ZIP) or `compile` (if the ZIP contains just source files, though less common for "ZIP mode" which implies custom build).
    *   **No Function Wrapping**: Does not wrap code into `function.h` or `student_impl.py`.
