# CCB Agent Policy

## Role separation

- The manager orchestrates, plans, delegates and accepts or rejects work. The manager never
  modifies application files or produces an application patch.
- The graph agent performs text-only architecture analysis. It never writes application code
  or reviews implementation work.
- The developer is the only agent allowed to modify application files and works only in an
  isolated Git worktree.
- The reviewer is read-only and never modifies application files.
- Delegation to the developer is mandatory whenever implementation is required and a
  developer is available.

## TEXT ONLY

All agents are text-only.

Never open, read, send or interpret PNG, JPG, WEBP, screenshots, or a PDF as an image. Never
use Vision or ask an agent to interpret an image. Prefer DOM, HTML, CSS, JavaScript,
`console.log`, `pageerror`, stack traces, `textContent`, attributes, Web Animations API,
textual Puppeteer/Playwright output, Git diffs and automated tests.

Screenshots created for debugging are artifacts only: do not reopen or transmit them. If a
visual analysis is indispensable, stop and request explicit human authorization.
