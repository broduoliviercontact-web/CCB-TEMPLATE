# Project profiles

Profiles are local declarative data in `profiles/`. Each has a safe `profile.conf`, a description,
a memory seed and optional text-only skills. Available profiles are `generic`, `react-web`,
`node-api`, `python`, `godot`, `audio-midi` and `max-msp`.

Install one with `./scripts/install-project.sh TARGET --profile react-web`. The selected ID is
recorded in `.ccb/active-profile`; its seed is kept in a marked block in shared memory. Re-running
the same profile does not duplicate the block. Changing profile with `--update` backs up the old
active-profile file and preserves previous profile files and project-owned skills.

To add a future profile, use a lowercase ID with digits and dashes, create all required files and
declare only skills located inside that profile. Profile paths, `..`, unknown configuration keys
and unsafe IDs are rejected. No profile is downloaded or executed.
