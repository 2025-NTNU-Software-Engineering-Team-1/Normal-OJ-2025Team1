# Function Only Submission Flow

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

    User->>Frontend: Upload Code (Zip/File)
    Frontend->>Frontend: Validate Format (acceptedFormat)
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
    
    Note over Dispatcher: Detects executionMode="functionOnly"<br/>and buildStrategy="makeFunctionOnly"

    Dispatcher->>Dispatcher: _prepare_with_build_strategy()
    Dispatcher->>BuildStrategy: prepare_function_only_submission()
    BuildStrategy->>BuildStrategy: Extract 'makefile' asset
    BuildStrategy->>BuildStrategy: Read student code (main.c/cpp/py)
    BuildStrategy->>BuildStrategy: Write to function.h / student_impl.py
    BuildStrategy-->>Dispatcher: BuildPlan (needs_make=True)

    Dispatcher->>Dispatcher: queue.put(job.Build)
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
    Dispatcher->>Dispatcher: PUT /submission/{id}/complete
    BackendAPI->>BackendModel: on_submission_complete()
    BackendModel->>BackendModel: process_result()
    BackendModel->>BackendModel: finish_judging()
```

## Detailed Steps

1.  **Frontend (`submit.vue`)**:
    *   User uploads a file or zip.
    *   `submit()` function calls `api.Submission.create` to get an ID.
    *   `submit()` function calls `api.Submission.modify` to upload the code.

2.  **Backend (`Back-End/model/submission.py` & `mongo/submission.py`)**:
    *   `create_submission`: Validates request and creates a `Submission` document.
    *   `update_submission`: Receives the file, calls `submission.submit(code)`.
    *   `Submission.submit`: Uploads code to MinIO (`_put_code`), then calls `send()`.
    *   `Submission.send`: Sends a POST request to the Sandbox's `/submit/<id>` endpoint with the code and metadata.

3.  **Sandbox (`Sandbox/app.py` & `dispatcher/dispatcher.py`)**:
    *   `app.py`: Calls `DISPATCHER.prepare_submission_dir` to extract files.
    *   `app.py`: Calls `DISPATCHER.handle` to queue the job.
    *   `Dispatcher.handle`:
        *   Reads `meta.json` (created by `testdata.py` fetching from Backend).
        *   Identifies `buildStrategy` as `makeFunctionOnly`.
        *   Calls `_prepare_with_build_strategy` -> `prepare_function_only_submission`.
    *   `prepare_function_only_submission` (`dispatcher/build_strategy.py`):
        *   Fetches and extracts the `makefile` asset.
        *   Reads the student's `main.c`/`cpp`/`py`.
        *   Writes the content to `function.h` (C/C++) or `student_impl.py` (Python) in `src/common`.
        *   Returns a `BuildPlan` with `needs_make=True`.
    *   `Dispatcher.run`:
        *   Executes the build using `make`.
        *   Executes the test cases using `Runner`.
        *   Collects results and sends them back to the Backend via `PUT /submission/<id>/complete`.
