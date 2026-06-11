# Constraint Rules: Minimalist Execution

## Code Generation & Modification
- Execute ONLY the exact changes, implementations, or fixes requested. 
- Do not add boilerplate, extra features, or modular cleanups unless explicitly told to.
- Use a direct "fix-and-code" approach with zero intermediate steps.

## Documentation & Walkthroughs
- DO NOT generate, update, or modify markdown files, implementation plans, checklists, or walkthrough files (`WALKTHROUGH.md`, `PLAN.md`, etc.).
- Provide code directly in the target files without explaining it in the chat unless asked.

## Tool Execution Constraints
- DO NOT execute background `flutter analyze` or `dart analyze` loops for minor or local file edits unless code structural validation fails.
- Avoid using dynamic subagents for trivial tasks.