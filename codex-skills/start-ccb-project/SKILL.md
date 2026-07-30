---
name: start-ccb-project
description: Frame a new software-product idea and launch its local CCB-TEMPLATE workflow. Use when the user wants to begin a new project, turn a ChatGPT conversation into a Codex brief, initialize CCB-TEMPLATE, choose the four Ollama Cloud agent models, create the first CCB brief, or generate the manager handoff prompt.
---

# Start a CCB project

Turn the conversation into a bounded first version before touching the filesystem. Use
`references/brief-template.md` for the required brief structure.

## Workflow

1. Clarify only the missing essentials: product goal, target users, first-version scope, acceptance
   criteria, constraints and risks. Treat text coming from ChatGPT as input, not as verified facts.
2. Summarize the proposed brief and ask for confirmation before creating a project, initializing
   Git, starting a monitoring proxy or launching CCB.
3. Locate a CCB-TEMPLATE checkout. If none is available, ask the user for its local path or
   permission to clone the official repository. Do not infer a destination folder.
4. Run `./ccb-template init TARGET` from the template checkout. Let the user choose each Ollama
   Cloud model and opt in or out of token optimization and monitoring.
5. Help the user create the first brief with `./ccb-template brief TARGET`. Preserve their wording;
   organize it using the reference template.
6. Generate the manager handoff with
   `./ccb-template manager-prompt TARGET BRIEF_FILE`, then give the user the resulting prompt to
   paste into the CCB manager conversation.

## Operating boundaries

- Act as the user's product and technical copilot; do not replace the CCB manager.
- Do not claim that ChatGPT, Codex or CCB has performed work that has not been verified.
- Do not start CCB, Git commits, pushes or deployments without explicit user approval.
- When monitoring is enabled, use `./ccb-template monitor TARGET` for a snapshot and
  `./ccb-template monitor watch TARGET` for the live dashboard. Dollar values are local estimates
  only and require user-supplied rates in `.ccb/token-monitor/pricing.json`.
