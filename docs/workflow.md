# Workflow

1. Run the preflight checks in `scripts/validate-ccb.sh`.
   `./scripts/ccb.sh` may be used as an optional interactive entry point; it does not replace
   scriptable commands or the validation gate.
2. The manager clarifies the objective and acceptance criteria.
3. The manager delegates text-only technical analysis to graph when useful and UX/UI analysis
   to graphiste when useful; those analyses may run independently or in parallel.
4. The manager creates an implementation plan and delegates implementation to developer.
5. The developer works in an isolated worktree, runs relevant tests and reports its diff.
6. The reviewer checks the diff, tests and regressions without modifying code.
7. The manager consolidates the result. Commits, merges, pushes and deployments require
   explicit human authorization.

Stop the workflow when Git has no `HEAD`, CCB policy files are missing, a required agent is
unavailable, validation fails without explanation, or a request is materially ambiguous.

## Skills partagés

Le dossier `skills/shared/` contient des contrats textuels légers pour les handoffs, la mémoire,
les limites Git et TEXT ONLY. Ils servent de référence et ne remplacent jamais
`.ccb/AGENT_POLICY.md`; consulter seulement les skills nécessaires à la mission.
