# dataproduct-builder-dbt — agent manifest

> **This file is the plugin's authoritative routing manifest, not a template.** It lives at the plugin's repo root and is meant to be **referenced** from your project (e.g. via Codex CLI's marketplace install, or a one-line pointer in your project's own `AGENTS.md`), not copied into your project. Updating the plugin updates this file in place.

This repository is a coding-agent plugin that helps build dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It exposes its capabilities as **skills** — markdown files under `skills/<name>/SKILL.md` that you read top-to-bottom and execute step by step.

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.** Each skill contains audit steps, parameter-gathering, and explicit user-confirmation gates that must not be skipped.

## Skills

| When the user asks about… | Follow this skill |
|---|---|
| Designing a new data product before any code (business question, candidate input ports, grain, contract draft, owning team) | `skills/dataproduct-design/SKILL.md` |
| Scaffolding a brand-new dbt data product from scratch (greenfield, empty directory) | `skills/dataproduct-bootstrap/SKILL.md` |
| Auditing an existing dbt project against the Entropy Data layout and adding what's missing (ODPS, ODCS, OpenLineage, GitHub Actions, git connections) | `skills/entropy-data-sync/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id — derive dbt output-port models from the ODCS schema | `skills/dataproduct-implement/SKILL.md` |
| Editing a data contract (`datacontracts/*.odcs.yaml`) and testing whether the change is breaking | `skills/datacontract-edit/SKILL.md` |
| Uploading example / sample rows for a data product to Entropy Data | `skills/dataproduct-exampledata-upload/SKILL.md` |
| Listing teams in Entropy Data (e.g. to pick `TEAM_NAME` as the data product owner) | `skills/team-list/SKILL.md` |
| Logging in to Entropy Data / setting up the API key for the CLI | `skills/entropy-data-connect/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative. Skills can also call other skills — e.g. `dataproduct-design` hands off to `dataproduct-bootstrap`, which hands off to `entropy-data-sync`; every platform-touching skill calls `entropy-data-connect` as its Step 0.

## Subagents

- **`agents/pii-scanner.md`** — read-only specialist that classifies columns in a sample dataset as `keep` / `drop` / `hash` and returns a structured scrub plan. Dispatched by `dataproduct-exampledata-upload` Step 2 on Claude Code; other agents fall back to inline scrubbing rules in the same step. Subagents are a Claude Code feature — Codex/Copilot ignore the `agents/` directory.

## Resolving `${PLUGIN_ROOT}`

The skill files reference `${PLUGIN_ROOT}` to locate `settings.json` and `templates/`. On Claude Code this is set automatically as `${CLAUDE_PLUGIN_ROOT}`; on Codex / Cursor / other agents reading this file, it is **not** set — resolve it as **the directory that contains this `AGENTS.md`** (the cloned repo root, which also contains `settings.json`, `.mcp.json`, and `skills/`).

## MCP server

Several skills call tools on the Entropy Data MCP server at `https://app.entropy-data.com/mcp` (search/fetch data products, get/save/test data contracts, request access, execute queries). The `.mcp.json` file in this repo is in Claude Code / Claude Desktop config format. For Codex or other MCP-capable CLIs, register the same URL via the host CLI's MCP configuration — consult that tool's docs for how.

If the MCP server is not configured, skills that need it will fail; surface the error to the user and stop rather than improvising a workaround.

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
