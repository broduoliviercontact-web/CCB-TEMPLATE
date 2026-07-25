# Architecture

CCB is a workflow layer around a Git repository and managed coding agents. Persistent project
instructions live under `.ccb/`; runtime state, sessions, worktrees and backups remain local
and are ignored.

```text
request → manager → graph and/or graphiste → developer (isolated worktree) → reviewer → manager
```

`graph` describes technical architecture, dependencies and code structure. `graphiste`
describes UX/UI, design tokens, layout and visual consistency from text-only evidence. The
template deliberately does not prescribe a programming language, UI framework, provider or
deployment system.

## Control Room and profiles

`scripts/ccb.sh` is an orchestration-only terminal entry point: it delegates installation,
validation and diagnosis to their dedicated scripts. Profiles in `profiles/` are declarative data
read by a safe parser; they add local memory seeds and text-only skills under `.ccb/profiles/`.
The CLI must not become a second implementation of those scripts’ business rules.
