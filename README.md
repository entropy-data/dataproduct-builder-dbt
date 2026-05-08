# dataproduct-builder-dbt

A coding-agent plugin that helps you build data products with [dbt](https://www.getdbt.com/) and integrate them with [Entropy Data](https://entropy-data.com).

## Status

Early access. The plugin ships eight skills and one subagent:

- **dataproduct-design** — designs a new data product *before* scaffolding: captures the business question, discovers candidate input ports via Entropy Data, decides grain and refresh cadence, drafts the output-port data contract, and picks the owning team. Produces a draft `<id>.odps.yaml` and `datacontracts/<contract>.odcs.yaml`, then hands off to bootstrap (greenfield) or sync (existing dbt project).
- **dataproduct-bootstrap** — scaffolds a brand-new dbt data product from scratch (greenfield): `dbt_project.yml`, model layout, README with `uv` install instructions, `profiles.yml.example` for the chosen warehouse, then hands off to the sync skill.
- **entropy-data-sync** — audits an existing dbt project against the Entropy Data reference layout (`<id>.odps.yaml`, `datacontracts/`, `openlineage.yml`, `models/{input_ports,staging,intermediate,output_ports}`, GitHub Actions workflow, git connections) and adds anything that is missing.
- **dataproduct-implement** — given an Entropy Data data product URL or id, fetches its data contracts and translates the ODCS schema into dbt models under `models/output_ports/v1/` (column list, types, tests). SQL bodies are left as TODOs — no invented business logic.
- **datacontract-edit** — edits a `datacontracts/*.odcs.yaml`, runs `datacontract test` against the live server, and classifies each failure as breaking-schema, breaking-quality, additive, or unrelated, with concrete fix suggestions.
- **dataproduct-exampledata-upload** — extracts ~20 sample rows via a non-prod dbt profile, drops PII columns flagged in the contract (and obvious name-based PII), and uploads the scrubbed sample with `entropy-data example-data put`. On Claude Code, dispatches to the `pii-scanner` subagent for the scrub plan; otherwise scrubs inline. Two explicit user confirmations before anything leaves the machine.
- **team-list** — lists the teams configured in Entropy Data so the user can pick a `TEAM_NAME` (used as the data product owner). Read-only; invoked by the bootstrap and sync skills when the user does not already know the team id.
- **entropy-data-connect** — ensures the `entropy-data` CLI has a working API-key connection to the user's organization. Validates an existing connection or walks the user through creating a user-scoped key. Invoked as Step 0 by every other skill that calls Entropy Data; can also be run directly to "log in".

Subagents (Claude Code only):

- **pii-scanner** — read-only specialist that classifies columns in a sample as `keep` / `drop` / `hash`, returning a structured scrub plan the calling skill applies verbatim. Dispatched by `dataproduct-exampledata-upload`.

## Install

The skills are plain markdown — any coding agent that can read instruction files can run them. Pick the install path for your CLI:

### Claude Code

```
/plugin install entropy-data/dataproduct-builder-dbt
```

`${CLAUDE_PLUGIN_ROOT}` is set automatically; the skills use it to find `settings.json` and the templates.

### Copilot CLI

Inside an interactive session:

```
/plugin install github.com/entropy-data/dataproduct-builder-dbt
```

Copilot CLI reads `skills/<name>/SKILL.md` and the `.mcp.json` shipped with this repo natively, so the skills and the Entropy Data MCP server are wired up after install. Verify with `/plugin list` and `/skills`. The plugin manifest at [`.github/copilot-instructions.md`](.github/copilot-instructions.md) provides the routing table the agent uses to pick the right skill.

### Codex CLI

Codex CLI's plugin install is marketplace-based; this repo does not yet ship a `marketplace.json`, so install manually:

1. Clone the plugin to a stable location:

   ```
   git clone https://github.com/entropy-data/dataproduct-builder-dbt.git ~/.codex/plugins/dataproduct-builder-dbt
   ```

2. Register the MCP server in `~/.codex/config.toml`:

   ```toml
   [mcp_servers.entropy-data]
   type = "http"
   url = "https://app.entropy-data.com/mcp"
   ```

3. Make the skills discoverable by Codex. User-scoped (available in every project):

   ```
   ln -s ~/.codex/plugins/dataproduct-builder-dbt/skills/* ~/.codex/skills/
   ```

   Or repo-scoped (available only in this dbt project), from your dbt project root:

   ```
   mkdir -p .agents/skills
   ln -s ~/.codex/plugins/dataproduct-builder-dbt/skills/* .agents/skills/
   ```

The plugin manifest at [`AGENTS.md`](AGENTS.md) is the routing table — once Codex picks up the skills, it follows that file to choose the right one. A native `codex marketplace add entropy-data/dataproduct-builder-dbt` flow will land once a `marketplace.json` is published.

### Other agents (Cursor, Aider, etc.)

Most agents that read `AGENTS.md` will pick up the routing manifest at the repo root automatically when invoked from inside the cloned plugin. For agents invoked from your own project, point them at the plugin's `AGENTS.md` from your project's instruction file, or follow the Codex-style manual MCP + skills setup adapted to your tool.

## Use

**Greenfield** — in an empty directory, ask the agent:

> Bootstrap a new dbt data product for Entropy Data.

The `dataproduct-bootstrap` skill will gather the parameters, scaffold the dbt project, then run `entropy-data-sync` to add the publishing layer.

**Existing dbt project** — open the project and ask:

> Make sure this dbt project is integrated with Entropy Data.

The `entropy-data-sync` skill will audit, report what is missing, and create the missing files.

## MCP server

The plugin auto-installs the **Entropy Data MCP** server (`https://app.entropy-data.com/mcp`) so the agent can discover data products, fetch and save data contracts, request access, run `datacontract test`, and execute queries. Authorization happens on first tool call (OAuth, same flow as `/mcp add`).

Self-hosters: edit `mcpServers.entropy-data.url` in [`.mcp.json`](.mcp.json) and `mcpUrl` in [`settings.json`](settings.json) to your deployment's host.

## Configuration

Plugin defaults live in [`settings.json`](settings.json) at the plugin root:

```json
{
  "apiHost": "https://api.entropy-data.com",
  "mcpUrl": "https://app.entropy-data.com/mcp"
}
```

| Key | Default | Description |
|---|---|---|
| `apiHost` | `https://api.entropy-data.com` | Base URL of the Entropy Data REST API. Substituted into `openlineage.yml` and the GitHub Actions workflow when a skill scaffolds a project. |
| `mcpUrl` | `https://app.entropy-data.com/mcp` | URL of the Entropy Data MCP server. Used by skills that reference the MCP; the plugin manifest must be edited separately to actually rewire the server. |

## License

MIT
