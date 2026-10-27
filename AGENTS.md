# Agent Operating Directives

## 1. Session Startup & Onboarding (Read-Only Checkout)
- Do **not** mutate tracked repository files during onboarding or readiness checks.
- The repository supports **Node.js >=22** (including Node 24). Do **not** install a separate `node@22` runtime via `npm` if Node >=22 is already on `PATH`.
- To install the pinned Railway CLI outside the git checkout, run:
  ```bash
  ./scripts/install-railway-cli.sh
