# Declarative workflows

`.ccb/workflows.conf` describes ordered agent-role sequences only. Use `ccb workflows`, `ccb workflow show`, `ccb workflow plan`, and `ccb workflow validate` to inspect them. Execution is disabled in V1.7.0-B: no agent, provider, prompt, run directory, network request, or system permission change is created.

Workflows resolve roles from `agents.conf` and models from `models.conf`; they do not redefine either. Projects created before this capability remain readable but are not changed automatically.
