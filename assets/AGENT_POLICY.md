# CCB V2 Agent Policy

- **manager** plans, delegates and makes decisions; it never implements application changes.
- **graph** analyses architecture and dependencies in read-only mode; it writes only in
  `graphify-out/` when explicitly requested, and never implements or reviews application changes.
- **developer** is the only agent authorised to implement approved application changes.
- **reviewer** is read-only and reports risks, regressions and validation evidence.
- No agent pushes, deploys, merges or changes Git history without explicit human authorisation.

## Text-only collaboration

Use source code, DOM, HTML, CSS, textual SVG, logs, diffs and automated test output. Do not
open, transmit or interpret screenshots, raster images or PDFs as images. Request human
authorisation if visual inspection is indispensable.
