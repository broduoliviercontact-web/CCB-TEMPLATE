# Codex and CCB workflow

Use ChatGPT or another conversational tool to explore a product idea. Then use Codex to convert
the idea into an executable, bounded brief because Codex can inspect the local repository and
validate implementation evidence.

1. Create the project with `./ccb-template init /chemin/du/projet`.
2. Use Codex to refine the objective, scope, acceptance criteria and risks.
3. Create a brief with `./ccb-template brief /chemin/du/projet`; finish the text with `.` on its
   own line.
4. Run `./ccb-template manager-prompt /chemin/du/projet brief-YYYYMMDD-HHMMSS.md` and paste the
   output into the CCB manager conversation.
5. Keep Codex as the decision-making copilot while CCB's manager coordinates graph, developer and
   reviewer.

Codex does not replace the CCB manager: Codex helps frame and verify work with the user, whereas
the manager orchestrates the permanent CCB agents under `.ccb/AGENT_POLICY.md`.
