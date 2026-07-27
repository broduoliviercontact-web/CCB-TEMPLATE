# Declarative project agents

CCB 1.7.0 adds `.ccb/agents.conf`. It declares the available roles, their model role, concise description, and intended access level. Models remain defined in `.ccb/models.conf`; skills remain defined in `.ccb/skills.conf`.

```sh
./scripts/ccb.sh agents ./my-project
./scripts/ccb.sh agent show developer ./my-project
./scripts/ccb.sh agent validate ./my-project
```

The initial roles are `manager`, `graph`, `graphiste`, `developer`, and `reviewer`. `manager`, `graph`, and `reviewer` are `read-only`; `graphiste` and `developer` are `write`. These values express intended behavior only: V1.7.0-A does not enforce filesystem isolation or provide a sandbox.

The parser accepts only the fixed versioned `KEY=VALUE` schema, rejects symlinks, duplicate or unknown keys, and does not source or execute project configuration. The commands are read-only: they do not launch an agent, contact a provider, or use the network. Valid commands exit 0, invalid configuration exits 1, and invalid CLI usage exits 2.

Projects at 1.6.1 remain readable but have no agents configuration. Migration from 1.6.1 to 1.7.0 is deliberately not implemented. The historical 1.6.0 to 1.6.1 upgrade remains available.
