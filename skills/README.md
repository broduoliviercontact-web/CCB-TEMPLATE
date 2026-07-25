# Shared Skills

A skill in this template is a reusable text-based work contract: it tells an agent how to
perform a narrow kind of task and how to report the result. Skills are references, not a source
of additional permissions. `.ccb/AGENT_POLICY.md` remains the controlling policy.

The first four skills are shared by multiple agents. Roles should read only the skills useful
to their mission. Future technical skills can be added progressively after human review; no
external skill should be added without a prior audit.

| Skill | Utilité |
| --- | --- |
| `ccb-handoff` | Standardiser les transmissions |
| `project-memory` | Maintenir les mémoires propres |
| `safe-git-boundaries` | Définir les limites Git |
| `text-only-policy` | Garantir le travail sans Vision |
