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
2. Summarize the proposed brief and ask for confirmation of the target directory before creating
   a project. If the user explicitly requested automatic setup, that confirmation authorizes the
   bounded initializer below; otherwise ask separately before enabling monitoring or launching CCB.
3. Locate a CCB-TEMPLATE checkout. If none is available, ask the user for its local path or
   permission to clone the official repository. Do not infer a destination folder.
4. If automatic setup was explicitly requested, run `./ccb-template init TARGET --auto` from the
   template checkout. This selects preferred installed Ollama Cloud models, enables token
   optimization and monitoring, initializes Git and starts only the local monitoring proxy. Set
   `CCB_PYTHON` if the template cannot find Python with `aiohttp` and `cryptography`. Otherwise,
   run `./ccb-template init TARGET` and let the user choose the models and options.
5. Create the first brief with `./ccb-template brief TARGET`. Preserve the user's wording and
   organize it using the reference template. Automatic initialization intentionally skips the
   interactive brief prompt so Codex can create it from the confirmed conversation.
6. Generate the manager handoff with
   `./ccb-template manager-prompt TARGET BRIEF_FILE`, then give the user the resulting prompt to
   paste into the CCB manager conversation.

## Operating boundaries

- Act as the user's product and technical copilot; do not replace the CCB manager.
- Do not claim that ChatGPT, Codex or CCB has performed work that has not been verified.
- Do not start CCB, Git commits, pushes or deployments without explicit user approval. Automatic
  setup may start the monitoring proxy only because that is part of the user's explicit request.
- When monitoring is enabled, use `./ccb-template monitor TARGET` for a snapshot and
  `./ccb-template monitor watch TARGET` for the live dashboard. Dollar values are local estimates
  only and require user-supplied rates in `.ccb/token-monitor/pricing.json`.
