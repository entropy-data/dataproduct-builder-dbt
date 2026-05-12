# dataproduct-builder-dbt

A coding-agent plugin that helps you build data products with [dbt](https://www.getdbt.com/) and integrate them with [Entropy Data](https://entropy-data.com).

## Skills

The plugin ships seven skills:

- **dataproduct-design** — designs a new data product *before* scaffolding: captures the business question, discovers candidate input ports via Entropy Data, decides grain and refresh cadence, drafts the output-port data contract, and picks the owning team. Produces a draft `<id>.odps.yaml` and `datacontracts/<contract>.odcs.yaml`, then hands off to bootstrap (greenfield) or sync (existing dbt project).
- **dataproduct-bootstrap** — scaffolds a brand-new dbt data product from scratch (greenfield): `dbt_project.yml`, model layout, README with `uv` install instructions, `profiles.yml.example` for the chosen warehouse, then hands off to the sync skill.
- **entropy-data-sync** — audits an existing dbt project against the Entropy Data reference layout (`<id>.odps.yaml`, `datacontracts/`, `openlineage.yml`, `models/{input_ports,staging,intermediate,output_ports}`, GitHub Actions workflow, git connections) and adds anything that is missing.
- **dataproduct-implement** — given an Entropy Data data product URL or id, fetches its data contracts and translates the ODCS schema into dbt models under `models/output_ports/v1/` (column list, types, tests). SQL bodies are left as TODOs — no invented business logic.
- **datacontract-edit** — edits a `datacontracts/*.odcs.yaml`, runs `datacontract test` against the live server, and classifies each failure as breaking-schema, breaking-quality, additive, or unrelated, with concrete fix suggestions.
- **dataproduct-exampledata-upload** — extracts ~20 sample rows via a non-prod dbt profile, drops PII columns flagged in the contract (and obvious name-based PII), and uploads the scrubbed sample with `entropy-data example-data put`. Two explicit user confirmations before anything leaves the machine.
- **team-list** — lists the teams configured in Entropy Data so the user can pick a `TEAM_NAME` (used as the data product owner). Read-only; invoked by the bootstrap and sync skills when the user does not already know the team id.

Skills assume the `entropy-data` CLI is already authenticated. Run `entropy-data connection add <name> --host <host> --api-key <key>` once before invoking any platform-touching skill.

## Install

The skills are plain markdown — any coding agent that can read instruction files can run them. Pick the install path for your CLI:

### Claude Code

Inside an interactive session:

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-dbt
/plugin install dataproduct-builder-dbt@dataproduct-builder-dbt
```

`${CLAUDE_PLUGIN_ROOT}` is set automatically; the skills use it to find the templates. See the [Claude Code plugin docs](https://code.claude.com/docs/en/discover-plugins) for details.

### OpenAI Codex

Add the marketplace from the terminal:

```
codex plugin marketplace add https://github.com/entropy-data/dataproduct-builder-dbt
```

Then open Codex, run `/plugins`, and pick `dataproduct-builder-dbt` from the directory. Codex reads the marketplace catalog at [`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json) and the per-plugin manifest at [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json), wiring up skills and the ODCS-lint hook automatically. The routing table at [`AGENTS.md`](AGENTS.md) tells the agent how to pick the right skill. See the [Codex plugin docs](https://developers.openai.com/codex/plugins) for details.

### GitHub Copilot CLI

Inside an interactive session:

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-dbt
/plugin install dataproduct-builder-dbt@dataproduct-builder-dbt
```

Copilot CLI reads `skills/<name>/SKILL.md` natively, so the skills are wired up after install. Verify with `/plugin list` and `/skills`. The routing table at [`.github/copilot-instructions.md`](.github/copilot-instructions.md) tells the agent how to pick the right skill. See the [Copilot CLI plugin docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing) for details.

### Connect

The skills authenticate against Entropy Data through a connection registered with the [entropy-data CLI](https://github.com/entropy-data/entropy-data-cli) (requires [uv](https://docs.astral.sh/uv/)).

Create a user-scoped key in the Entropy Data web UI (**Organization Settings → API Keys → Create new API key**, scope `User (personal token)`), install the CLI, and register the connection:

```
uv tool install --upgrade entropy-data
entropy-data connection add default --api-key <your-api-key> --host <your-entropy-data-host>
```

Every skill picks up the active connection, so `--host` doubles as the configuration knob for self-hosted Entropy Data deployments. For CI workflows, register a connection with a team-scoped or organization-scoped API key.

### Other agents (Cursor, Aider, etc.)

Most agents that read `AGENTS.md` will pick up the routing manifest at the repo root automatically when invoked from inside the cloned plugin. For agents invoked from your own project, point them at the plugin's `AGENTS.md` from your project's instruction file, or follow the Codex-style skills setup adapted to your tool.

## Use

**Greenfield** — in an empty directory, ask the agent:

> Bootstrap a new dbt data product for Entropy Data.

The `dataproduct-bootstrap` skill will gather the parameters, scaffold the dbt project, then run `entropy-data-sync` to add the publishing layer.

**Existing dbt project** — open the project and ask:

> Make sure this dbt project is integrated with Entropy Data.

The `entropy-data-sync` skill will audit, report what is missing, and create the missing files.

## Configuration

The plugin reads the Entropy Data host from the active `entropy-data` CLI connection (`entropy-data connection get -o json` → `host`). Run `entropy-data connection add <name> --host <host> --api-key <key>` once and every skill picks up the same host — for self-hosted Entropy Data deployments, point that `--host` at your deployment URL.

## Customization

This plugin is a starting point, not a finished product. Organizations with their own data-product stack, naming conventions, or self-hosted Entropy Data deployment are encouraged to **fork or copy this repository** and adapt it to their environment.

Common extension points:

- **Templates** under [`skills/dataproduct-bootstrap/templates/`](skills/dataproduct-bootstrap/templates/) and [`skills/entropy-data-sync/templates/`](skills/entropy-data-sync/templates/) — these ship the ODPS, ODCS, OpenLineage transport, GitHub Actions workflow, and dbt project skeleton that the bootstrap and sync skills install. Replace any of them to match your conventions (e.g. swap GitHub Actions for GitLab CI, change the model layer naming, embed company-specific tags).
- **Skills** — add your own `skills/<name>/SKILL.md` for organization-specific flows: internal data-quality checks, governance approvals, downstream sync to your data catalog, etc. Update `AGENTS.md` and `.github/copilot-instructions.md` so the routing tables surface them.
- **Hooks** — extend [`hooks/hooks.json`](hooks/hooks.json) with additional `PostToolUse` validators (e.g. an internal lint on `models/**/*.sql`, or a check that team names match your IdP).
- **Subagents** — add Claude Code subagents under `agents/` for read-only specialist roles (e.g. a PII scanner tuned to your classification taxonomy, a contract-review specialist for your terms-of-use boilerplate).

After customizing, rename the plugin in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) and [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json), then publish under your own GitHub organization or GitLab repository. Internal users install with `/plugin marketplace add <your-repo-url>` followed by `/plugin install <your-fork>@<your-fork>` (Claude Code, Copilot CLI), or `codex plugin marketplace add <your-repo-url>` then `/plugins` in Codex.

If a change you've made is broadly useful, [open an issue or PR upstream](https://github.com/entropy-data/dataproduct-builder-dbt/issues), generic improvements are very welcome.

## License

MIT
