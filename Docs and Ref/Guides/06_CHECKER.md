# Custom Checker Guide

This document explains how to develop and use Custom Checkers in Normal-OJ.

## 1. Overview

The Normal-OJ evaluation system consists of two phases:
1.  **Checker Phase**: Verifies the correctness of the student's program output.
2.  **Scoring Phase**: Calculates the final score based on test results.

## 2. Default Checker

The default checker uses **line-by-line string comparison**, ignoring trailing whitespace and trailing empty lines.

**Comparison Rules:**
1.  Remove trailing whitespace from each line.
2.  Remove empty lines at the end of the file.
3.  Compare student output with the standard answer line by line.

**Use Cases:**
- Unique and fixed answer format.
- No fault tolerance required.
- Simple input/output problems.

## 3. Custom Checker

When a problem requires more complex verification logic (e.g., floating-point error, multiple solutions, special formats), a Custom Checker can be used.

### Checker Specification

**Filename:** `checker.py` (Uploaded as any name, executed as `custom_checker.py`).

**Execution Environment:** Python 3 (Inside Docker container).

**Arguments:**
The Checker receives three file paths via command-line arguments (`sys.argv`).

| Index | Variable | Description | Example Path (Container) |
| :--- | :--- | :--- | :--- |
| `sys.argv[1]` | `input_file` | **Testcase Input** (.in) | `/workspace/input.in` |
| `sys.argv[2]` | `output_file` | **Student Output** (.out) | `/workspace/student.out` |
| `sys.argv[3]` | `answer_file` | **Standard Answer** (.out) | `/workspace/answer.out` |

**Output Requirements (Stdout):**
The Checker must output the judgment result to standard output (stdout). The system parses the following keywords (case-insensitive):

-   `STATUS: <status>`
-   `MESSAGE: <message>`

**Status Values:**
-   `AC` - Accepted
-   `WA` - Wrong Answer
-   (Missing STATUS or other values result in `JE` - Judgment Error)

### Checker Template

```python
#!/usr/bin/env python3
import sys

def check(input_path, student_path, answer_path):
    try:
        with open(input_path, 'r') as f:
            input_data = f.read().strip()
        
        with open(student_path, 'r') as f:
            student_data = f.read().strip()
        
        with open(answer_path, 'r') as f:
            answer_data = f.read().strip()
        
        # Implement check logic
        if student_data == answer_data:
            return "AC", "Answer matches perfectly"
        else:
            return "WA", f"Expected '{answer_data}', got '{student_data}'"
            
    except Exception as e:
        return "WA", f"Checker error: {str(e)}"

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("STATUS: JE")
        print("MESSAGE: Invalid checker arguments")
        sys.exit(1)
    
    status, message = check(sys.argv[1], sys.argv[2], sys.argv[3])
    print(f"STATUS: {status}")
    print(f"MESSAGE: {message}")
```

### Advanced Example: Floating Point Comparison

```python
def check_float(input_path, student_path, answer_path, epsilon=1e-6):
    try:
        with open(student_path, 'r') as f:
            student_nums = [float(x) for x in f.read().split()]
            
        with open(answer_path, 'r') as f:
            answer_nums = [float(x) for x in f.read().split()]
            
        if len(student_nums) != len(answer_nums):
            return "WA", "Count mismatch"
            
        for i, (stu, ans) in enumerate(zip(student_nums, answer_nums)):
            if abs(stu - ans) > epsilon:
                return "WA", f"Diff at index {i}"
                
        return "AC", "Accepted"
    except ValueError:
        return "WA", "Output format error"
```

## 4. Interactive Mode Checker

In Interactive Mode, the Checker is handled by the Teacher Program, which reports results via the `Check_Result` file. Custom Checker (`checker.py`) is **not** used in Interactive Mode.

**Check_Result Format:**
```
STATUS: AC
MESSAGE: Correct solution
```

## 5. Best Practices

1.  **Error Handling**: Always use try-except. Return WA instead of crashing.
2.  **Efficiency**: Keep it efficient as it runs for every test case.
3.  **Message Quality**: Provide clear messages to help students debug (without leaking answers).
