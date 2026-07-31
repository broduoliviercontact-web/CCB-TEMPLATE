---
name: ccb-developer-delivery
description: Implement an approved change with focused validation.
---

# Developer delivery

1. Confirm the approved scope and inspect relevant existing conventions.
2. Verify the feature or fix is really needed before writing code.
3. Reuse existing helpers, the standard library, native platform features and already-installed dependencies before adding anything new.
4. Make the smallest correct maintainable change that meets the acceptance criteria.
5. Avoid unrequested abstractions, broad rewrites and avoidable dependencies.
6. Fix the common root cause of repeated bugs when the evidence supports it.
7. Add or adjust focused tests when behaviour changes or logic is nontrivial.
8. Never reduce validation, security, accessibility, error handling or data-loss protection to make the diff smaller.
9. Run relevant checks and report files changed, results and remaining limitations.

Do not push, deploy or change Git history without explicit approval.
