# Agent Operating Directives

## 1. Startup Behavior (Read-Only)
- Do not automatically deploy infrastructure or mutate tracked files on session start.
- To check environment readiness without changing any files, run:
  ```bash
  ./scripts/cce-init.sh --mode check
