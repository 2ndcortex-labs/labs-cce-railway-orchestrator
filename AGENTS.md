# Agent Operating Directives

## 1. Session Startup Rules (MANDATORY — Read First)
- **DO NOT** automatically run onboarding, project bootstrap, `@railway/cli` installation, or container deployment when a session starts.
- On your first turn (or whenever asked for status/readiness), run ONLY the non-destructive pre-flight check:
  ```bash
  ./scripts/cce-init.sh --mode check
