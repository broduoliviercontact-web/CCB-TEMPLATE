# Workflow

1. Run the preflight checks in `scripts/validate-ccb.sh`.
2. The manager clarifies the objective and acceptance criteria.
3. The manager delegates text-only architecture analysis to graph when it is useful.
4. The manager creates an implementation plan and delegates implementation to developer.
5. The developer works in an isolated worktree, runs relevant tests and reports its diff.
6. The reviewer checks the diff, tests and regressions without modifying code.
7. The manager consolidates the result. Commits, merges, pushes and deployments require
   explicit human authorization.

Stop the workflow when Git has no `HEAD`, CCB policy files are missing, a required agent is
unavailable, validation fails without explanation, or a request is materially ambiguous.
