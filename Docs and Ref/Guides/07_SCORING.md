# Custom Scoring Guide

This document explains how to develop and use Custom Scoring Scripts in Normal-OJ.

## 1. Overview

The Scoring Phase calculates the final score based on the results of the Checker Phase.

## 2. Default Scoring

When no Scoring Script is provided:
1.  **Subtask Scoring**: All cases in a subtask must be AC to get points.
2.  **Total Score**: Sum of all subtask scores.

## 3. Custom Scoring Script

Custom Scoring Scripts allow for complex scoring logic (e.g., partial credit, weighted scoring, time bonuses). They apply to both **General and Interactive** problem types.

### Scoring Script Specification

**Filename:** `score.py` (Only Python is supported).

**Execution Environment:** Python 3 (Container: `noj-custom-checker-scorer`, No Network).

**Input (Stdin):**
The system passes evaluation results in JSON format via standard input.

**Input JSON Schema (Draft):**
```json
{
  "submissionId": "...",
  "problemId": 123,
  "tasks": [
    {
      "taskIndex": 0,
      "taskScore": 30,
      "results": [
        {
          "caseIndex": 0,
          "status": "AC",
          "runTime": 15,
          "memoryUsage": 2048
        }
      ]
    }
  ],
  "totalScore": 0,
  "lateSeconds": 0,
  "stats": { ... }
}
```

**Output (Stdout):**
The script must output the scoring result in JSON format. If the script fails, times out, or outputs invalid JSON, the submission is marked as **JE** (Judgment Error).

**Output JSON Schema (Draft):**
```json
{
  "score": 85,
  "message": "Good job! -5 late penalty.",
  "breakdown": {
    "subtasks": [30, 40, 30],
    "latePenalty": -5
  }
}
```

### Scoring Script Template

```python
#!/usr/bin/env python3
import sys
import json

def calculate_score(data):
    total_score = data['totalScore']
    message = "Default scoring"
    
    # Example: Late penalty
    late_seconds = data.get('lateSeconds', 0)
    if late_seconds > 0:
        late_days = late_seconds / 86400
        penalty = int(late_days * 10)
        total_score = max(0, total_score - penalty)
        message = f"Late submission: -{penalty} points"
    
    return {
        "score": total_score,
        "message": message
    }

if __name__ == "__main__":
    try:
        data = json.load(sys.stdin)
        result = calculate_score(data)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({
            "score": 0,
            "message": f"Scoring error: {str(e)}"
        }))
        sys.exit(1)
```

## 4. Examples

### Example: Competition Mode (Count ACs)

```python
def calculate_score(data):
    ac_count = 0
    total_count = 0
    
    for task in data['tasks']:
        for result in task['results']:
            total_count += 1
            if result['status'] == 'AC':
                ac_count += 1
    
    return {
        "score": ac_count,
        "message": f"{ac_count}/{total_count} passed"
    }
```

## 5. Best Practices

1.  **Stability**: Handle all possible inputs. Ensure valid JSON output.
2.  **Fairness**: Scoring rules should be transparent to students.
3.  **Error Handling**: Gracefully handle unexpected data.
