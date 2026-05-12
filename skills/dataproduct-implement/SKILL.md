---
name: dataproduct-implement
description: Given an Entropy Data data product URL or id, fetch its data contracts, translate the contract schema into dbt models under models/output_ports/v1/, and ensure the project has the publishing layer (ODPS, ODCS, OpenLineage, GitHub Actions). Trigger when the user asks to "implement the data product <url>", "build the dbt pipeline for this data product", or "scaffold dbt models from a data contract".
---

# Implement a data product from its data contract

Turn an Entropy Data data product into a working dbt pipeline. The data contract (ODCS) is the source of truth for output schema; this skill reads it and writes the dbt artifacts that produce data matching the contract.

## When to use this vs. other skills

- **Empty directory, no dbt project yet** → run `dataproduct-bootstrap` first, then come back here.
- **Existing dbt project, need ODPS/ODCS/OpenLineage scaffolding only** → use `entropy-data-sync` instead.
- **Existing dbt project, want to derive models from a published data contract** → this skill.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **dataproduct-implement**. I'll:
> 1. Pre-checks: confirm this is a dbt project, the `dbt` CLI is installed, and the `entropy-data` CLI is connected.
> 2. Resolve the data product by id or URL (`entropy-data dataproducts get`).
> 3. Fetch each selected output port's data contract (`entropy-data datacontracts get`).
> 4. Translate the ODCS schema into dbt models under `models/output_ports/v1/` (column list, types, tests; SQL bodies as TODOs).
> 5. Hand off to `entropy-data-sync` to add any missing publishing artifacts (ODPS, OpenLineage, GitHub Actions).
> 6. Summarize what was generated and the open TODOs.

Then proceed.

### Step 0 — Pre-checks

- Confirm `dbt_project.yml` exists at the working directory root. If not, ask whether to run `dataproduct-bootstrap` first, then stop.
- Confirm `dbt --version` is on PATH. If not, stop and tell the user to install the dbt adapter for their warehouse (e.g. `uv tool install dbt-snowflake`, `uv tool install dbt-databricks`, `uv tool install dbt-bigquery`, `uv tool install dbt-postgres`).
- Confirm `entropy-data --version` is on PATH (install with `uv tool install entropy-data` if not) and `entropy-data connection test` succeeds. If the test fails, stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>`.

### Step 1 — Resolve the data product

Accept either:

- a full URL (e.g. `https://app.entropy-data.com/dataproducts/<id>`) — extract the trailing id, **or**
- a bare data product id.

Run `entropy-data dataproducts get <id> -o json`. Remember the response as `DATA_PRODUCT`. Extract:

- `DATA_PRODUCT_ID`, `DATA_PRODUCT_NAME`, owning team, purpose
- the list of output ports — each has an id, a server (catalog/schema/table), and a linked data contract id

If the data product has more than one output port, ask the user which one(s) to implement in this run. Default to all.

### Step 2 — Fetch the data contracts

For each selected output port, run `entropy-data datacontracts get <contract-id> -o json` with the contract id from the data product. Remember the response as `CONTRACT`. The fields you need:

- `models` (table name → list of fields with `type`, `required`, `unique`, `description`, `classification`)
- `servers` (so the output port's server config is consistent with the contract)
- `terms` and `quality` rules — useful context but not required to materialize the model

### Step 3 — Translate ODCS schema to dbt artifacts

For each contract:

1. Decide a dbt-side table name. Default: the `models` key in the contract. Confirm with the user if it differs from the output-port server's table name.
2. **Identify candidate input ports.** Run `entropy-data access list -o json` and filter to agreements where `DATA_PRODUCT_ID` is the consumer — those provider data products are the input ports this product can actually read. Only fall back to a broader `entropy-data search query` if the user asks. If `models/input_ports/` already has matching tables, prefer those.
3. Generate `models/output_ports/v1/<table>.sql` — a stub `select` that lists the contract columns explicitly with `cast(... as <warehouse-type>) as <column>`. **Leave the `from` clause as a TODO** with a comment listing the candidate input ports from the previous step; do not invent business logic.
4. Append the column list to `models/output_ports/v1/_models.yml` under `models:` — name, description (from contract), and tests derived from the contract: `not_null` for `required: true`, `unique` for `unique: true`, `accepted_values` if the contract defines an enum.
5. Map ODCS types to the warehouse dialect:

| ODCS `type` | Databricks | Snowflake | BigQuery | Postgres |
|---|---|---|---|---|
| `string`/`text` | `string` | `varchar` | `string` | `text` |
| `integer`/`long` | `bigint` | `number` | `int64` | `bigint` |
| `decimal`/`numeric` | `decimal(38,9)` | `number(38,9)` | `numeric` | `numeric` |
| `boolean` | `boolean` | `boolean` | `bool` | `boolean` |
| `timestamp` | `timestamp` | `timestamp_ntz` | `timestamp` | `timestamp` |
| `date` | `date` | `date` | `date` | `date` |

Pick the dialect from the contract's `servers[].type` (or, if absent, ask).

### Step 4 — Hand off to entropy-data-sync

Call the **entropy-data-sync** skill (in this same plugin) so any missing publishing artifacts get created (`<id>.odps.yaml`, `openlineage.yml`, `.github/workflows/data-product.yml`). Pass the parameters you already resolved in Step 1 so the user is not re-asked.

If `<id>.odps.yaml` already exists locally and disagrees with the fetched data product, **do not overwrite** — surface the diff and ask.

### Step 5 — Final report

End with this two-part recap. Use the same `Status` enum the other skills use: `created`, `updated`, `already present`, `deferred`, `skipped`.

**Part 1 — outcome table.** One row per output port implemented.

| Artifact | Status | Details |
|---|---|---|
| Data product | already present | `<DATA_PRODUCT_ID>` — fetched from platform |
| Data contract `<CONTRACT_ID>` | … | written to `datacontracts/<contract_id>.odcs.yaml` |
| Model `<table>.sql` | … | `models/output_ports/v1/<table>.sql` (SQL body left as TODO) |
| `_models.yml` entry for `<table>` | … | tests derived from the contract |
| `entropy-data-sync` handoff | … | "ran" / "skipped" — see sync's own report for ODPS/OpenLineage/workflow rows |

**Part 2 — next steps.** Bullet list, include only what applies:

- Fill in the `from` clause / business logic for each output-port model — one bullet per generated `<table>.sql` with the candidate input ports listed inline.
- Run `dbt run` and `dbt test` locally to verify the generated models compile and pass the contract-derived tests.
- Run the contract test: `datacontract test datacontracts/<file>.odcs.yaml` for each contract.
- Any deferred items from the sync skill's report.

If there is nothing in Part 2, write a single line: `No further action required.`

## Constraints

- **Contract is source of truth for schema, not logic.** Generate column names, types, and tests from the contract; do not invent SQL transformations. SQL bodies must be left as TODOs unless the user asks you to fill them.
- **Don't fetch contracts from disk if they exist locally** — always re-fetch via `entropy-data datacontracts get` so the implementation matches the published version. After fetch, write the contract to `datacontracts/<contract_id>.odcs.yaml` so it is version-controlled.
- **Don't overwrite existing dbt SQL files**. If `models/output_ports/v1/<table>.sql` already exists, surface the diff and ask before changing.
- **Idempotent**: re-running the skill with the same data product id should be a no-op when contract and local files already agree.
- **Do not commit or push** — leave VCS state to the user.
