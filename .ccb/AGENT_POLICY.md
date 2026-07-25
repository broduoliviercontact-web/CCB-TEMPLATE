# CCB Agent Policy

## Role separation and delegation

- **manager** orchestrates, plans, delegates and accepts or rejects work. The manager never
  modifies application files or produces an application patch.
- **graph** performs text-only technical architecture and dependency analysis. It never writes
  application code or reviews implementation work.
- **graphiste** provides visual direction, UX/UI, layout and graphic consistency
  recommendations. It may inspect textual HTML, CSS, textual SVG, design tokens, UI
  components, logs and DOM structure. It never modifies application files or produces an
  application patch; it reports recommendations to manager. It does not replace graph.
- **developer** is the only agent allowed to modify application files and works only in an
  isolated Git worktree.
- **reviewer** is read-only and never modifies application files.
- Delegation to developer is mandatory whenever implementation is required and a developer is
  available. Graph and graphiste may be consulted independently or in parallel.

Graphiste may write only to `graphiste-out/` after an explicit authorization from manager or
the user. Graph may write only to `graphify-out/` under the same condition.

## TEXT ONLY

All agents are text-only. Never open, read, send or interpret PNG, JPG, WEBP, screenshots, or
a PDF as an image. Never use Vision or ask an agent to interpret an image. Graphiste follows
this rule even for visual-direction work.

Prefer DOM, HTML, CSS, JavaScript, `console.log`, `pageerror`, stack traces, `textContent`,
attributes, Web Animations API, textual Puppeteer/Playwright output, Git diffs and automated
tests. Screenshots created for debugging are artifacts only: do not reopen or transmit them.
If visual analysis is indispensable, stop and request explicit human authorization.
