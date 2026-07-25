# Getting Started

Clone the template, then install its persistent policy files into a target Git project that
already has an initial commit:

```sh
git clone https://github.com/broduoliviercontact-web/CCB-TEMPLATE.git
cd CCB-TEMPLATE

./scripts/install-project.sh /chemin/vers/mon-projet
./scripts/install-project.sh /chemin/vers/mon-projet --profile generic
./scripts/doctor.sh /chemin/vers/mon-projet
./scripts/validate-ccb.sh /chemin/vers/mon-projet
```

The installer copies only missing persistent files, preserves existing memory files, and
updates only its marked `# BEGIN CCB TEMPLATE` block in the target `.gitignore`. It never
starts CCB or inspects provider credentials. Use `--update` to replace the shared policy after
backing up the old version under `.ccb/backups/`; memories remain preserved:

```sh
./scripts/install-project.sh /chemin/vers/mon-projet --update
```

`graphify-out/` and `graphiste-out/` are local artifact directories; only their `.gitkeep`
placeholders belong in this template.

Before starting an isolated developer worktree, create an initial Git commit so `HEAD` exists.
`doctor.sh` is read-only: it reports missing prerequisites and suggested commands without
installing tools or changing the target project. Use `--verbose` to include the validator report.

For an optional interactive entry point, run `./scripts/ccb.sh`. It opens the CCB Control Room;
all commands remain available non-interactively for CI and automation.
