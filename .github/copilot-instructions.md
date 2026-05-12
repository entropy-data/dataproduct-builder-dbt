# dataproduct-builder-dbt — Copilot CLI instructions

> **This file is the plugin's authoritative routing manifest, not a template.** It ships at the plugin's repo root and is loaded automatically when you install the plugin with `/plugin install github.com/entropy-data/dataproduct-builder-dbt`. Don't copy it into your project — when the plugin updates, this file updates with it.

This repository is a coding-agent plugin that helps build dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It exposes its capabilities as **skills** — markdown files under `skills/<name>/SKILL.md` that you read top-to-bottom and execute step by step.

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.** Each skill contains audit steps, parameter-gathering, and explicit user-confirmation gates that must not be skipped.

## Skills

| When the user asks about… | Follow this skill |
|---|---|
| Scaffolding a brand-new dbt data product from scratch (greenfield, empty directory) | `skills/dataproduct-bootstrap/SKILL.md` |
| Auditing an existing dbt project against the Entropy Data layout and adding what's missing (ODPS, ODCS, OpenLineage, GitHub Actions, git connections) | `skills/entropy-data-sync/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id — derive dbt output-port models from the ODCS schema | `skills/dataproduct-implement/SKILL.md` |
| Editing a data contract (`datacontracts/*.odcs.yaml`) and testing whether the change is breaking | `skills/datacontract-edit/SKILL.md` |
| Uploading example / sample rows for a data product to Entropy Data | `skills/dataproduct-exampledata-upload/SKILL.md` |
| Listing teams in Entropy Data (e.g. to pick `TEAM_NAME` as the data product owner) | `skills/entropy-data-teams/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative. Skills can also call other skills — e.g. `dataproduct-bootstrap` hands off to `entropy-data-sync`. Platform-touching skills verify the `entropy-data` CLI connection with `entropy-data connection test` as their Step 0 and abort if it fails; they do not prompt for credentials themselves.

## Resolving `${PLUGIN_ROOT}`

The skill files reference `${PLUGIN_ROOT}` to locate `templates/`. On Claude Code this is set automatically as `${CLAUDE_PLUGIN_ROOT}`; on Copilot CLI it is **not** set — resolve it as the cloned repo root (the directory that contains `skills/`; i.e. the parent of the `.github/` directory containing this file).

## CLIs the skills shell out to

- **`entropy-data`** (PyPI: `entropy-data`; install with `uv tool install entropy-data`) — used to publish data products / contracts, configure git connections, list teams, upload example data. Auth is API-key based (`ENTROPY_DATA_API_KEY` env var, `--api-key` flag, or `entropy-data connection add` storing keys in `~/.entropy-data/config.toml`).
- **`datacontract`** — used by `datacontract-edit` to run schema and quality tests against a server defined in the ODCS file.

If either CLI is missing, surface the install instruction and stop — do not try to install on the user's behalf without confirmation.

## Conventions when running skills

- **Don't skip the audit.** Skills that modify the project audit existing state first and ask the user to confirm before writing.
- **Don't overwrite existing files silently.** When a target file is present but differs, surface the diff and ask.
- **Don't run `git init`, commit, or push** on the user's behalf — leave VCS state to the user unless the skill explicitly says otherwise.
- **Don't commit secrets.** API keys and credentials must come from env vars or repo secrets, never from committed files.
- **Idempotent re-runs.** Running a skill a second time when everything is already in place should be a no-op.
