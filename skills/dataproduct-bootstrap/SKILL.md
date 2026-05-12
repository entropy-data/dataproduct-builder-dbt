---
name: dataproduct-bootstrap
description: Bootstrap a brand-new dbt data product from scratch — create dbt_project.yml, the Entropy Data model layout (input_ports, staging, intermediate, output_ports/v1), README with uv install instructions, .gitignore, and a profiles.yml.example for the chosen warehouse. After scaffolding, hands off to the entropy-data-sync skill to add the publishing layer (ODPS, ODCS, OpenLineage, GitHub Actions). Trigger when the user asks to start a new data product, scaffold a new dbt project, or "create a data product from scratch."
---

# Bootstrap a new dbt data product

Create a new dbt data product project that follows the Entropy Data conventions. This skill handles the **greenfield** case — empty directory, no dbt project yet. For an existing dbt project that just needs the Entropy Data layer, use the **entropy-data-sync** skill instead.

## What this skill produces

After running, the directory contains:

```
.
├── dbt_project.yml
├── .gitignore
├── README.md
├── profiles.yml.example
├── models/
│   ├── input_ports/_models.yml
│   ├── staging/_models.yml
│   ├── intermediate/_models.yml
│   └── output_ports/v1/_models.yml
├── analyses/      # empty
├── macros/        # empty
├── seeds/         # empty
├── snapshots/     # empty
└── tests/         # empty
```

It then invokes **entropy-data-sync** to add `<id>.odps.yaml`, `datacontracts/`, `openlineage.yml`, and `.github/workflows/data-product.yml`.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Step 1 — Pre-checks

- Confirm the working directory is empty, or that it contains only files the user is fine with (e.g. an empty git repo, a `LICENSE`, or a `README.md` that will be overwritten).
- If `dbt_project.yml` already exists, **stop** and tell the user to use the `entropy-data-sync` skill instead. This skill is for greenfield only.

### Step 2 — Gather parameters in one batched question

Ask the user for these in a single prompt. Do not generate any files until you have all of them.

| Parameter | Description | Example |
|---|---|---|
| `DATA_PRODUCT_ID` | Stable id, snake_case, also the dbt project name | `dp_acme_customer_activity` |
| `DATA_PRODUCT_NAME` | Human-friendly name | `Customer Activity` |
| `PURPOSE` | One sentence — why this data product exists | `Customer activity for customer success.` |
| `TEAM_NAME` | Owning team | `customer-success` (see note below) |
| `PLATFORM` | `databricks`, `snowflake`, `bigquery`, or `postgres` | `databricks` |
| `CATALOG` (or equivalent) | Databricks catalog / Snowflake database / BigQuery project / Postgres database | `entropy_data_prod` |
| `SCHEMA` | Schema / dataset | `dp_acme_customer_activity` |
| `TABLE` | First output port table name | `customer_activity` |

Set `DBT_PROJECT_NAME = DATA_PRODUCT_ID`.

**Picking `TEAM_NAME`**: prefer a team `id` that already exists in Entropy Data so the data product slots into the team-scoped views in the UI. If the user does not already know the team id, invoke the **entropy-data-teams** skill (in this same plugin), let them pick, and use the returned `id` as `TEAM_NAME`. A free-text value is still accepted (the ODPS schema does not enforce membership), but the registered id is preferred.

### Step 3 — Pick the dbt adapter and profile block

Map `PLATFORM` to the right dbt adapter package and the `profiles.yml.example` body:

| PLATFORM | `DBT_ADAPTER` | `PROFILE_BLOCK` (substituted into `profiles.yml.example`) |
|---|---|---|
| `databricks` | `dbt-databricks` | `type: databricks`<br/>`catalog: <CATALOG>`<br/>`schema: <SCHEMA>`<br/>`host: <fill in>`<br/>`http_path: <fill in>`<br/>`token: <fill in>`<br/>`threads: 4` |
| `snowflake` | `dbt-snowflake` | `type: snowflake`<br/>`account: <fill in>`<br/>`user: <fill in>`<br/>`password: <fill in>`<br/>`role: <fill in>`<br/>`database: <CATALOG>`<br/>`warehouse: <fill in>`<br/>`schema: <SCHEMA>`<br/>`threads: 4` |
| `bigquery` | `dbt-bigquery` | `type: bigquery`<br/>`method: oauth`<br/>`project: <CATALOG>`<br/>`dataset: <SCHEMA>`<br/>`location: <fill in>`<br/>`threads: 4` |
| `postgres` | `dbt-postgres` | `type: postgres`<br/>`host: <fill in>`<br/>`user: <fill in>`<br/>`password: <fill in>`<br/>`port: 5432`<br/>`dbname: <CATALOG>`<br/>`schema: <SCHEMA>`<br/>`threads: 4` |

### Step 4 — Scaffold the dbt project

Templates are at `${PLUGIN_ROOT}/skills/dataproduct-bootstrap/templates/`. Copy each template into the working directory, substituting placeholders.

| Template | Destination |
|---|---|
| `dbt_project.yml` | `dbt_project.yml` |
| `.gitignore` | `.gitignore` (merge if one already exists; do not overwrite) |
| `README.md` | `README.md` (merge or back up if one already exists) |
| `profiles.yml.example` | `profiles.yml.example` |
| `models/input_ports/_models.yml` | `models/input_ports/_models.yml` |
| `models/staging/_models.yml` | `models/staging/_models.yml` |
| `models/intermediate/_models.yml` | `models/intermediate/_models.yml` |
| `models/output_ports/v1/_models.yml` | `models/output_ports/v1/_models.yml` |

Also create empty directories `analyses/`, `macros/`, `seeds/`, `snapshots/`, `tests/`. If a directory cannot be empty in git, drop a single `.gitkeep` file.

### Step 5 — Hand off to entropy-data-sync

Now the dbt skeleton is in place. Invoke the **entropy-data-sync** skill (in this same plugin) to add ODPS, ODCS, OpenLineage transport, and the GitHub Actions workflow.

Pass the parameters you already collected (`DATA_PRODUCT_ID`, `DATA_PRODUCT_NAME`, `PURPOSE`, `TEAM_NAME`, `PLATFORM`, `CATALOG`, `SCHEMA`, `TABLE`) so the user does not have to answer them again. `entropy-data-sync` resolves `API_HOST` itself from the entropy-data CLI connection.

The integration skill will run its own audit — since this is a fresh project, every artifact will be reported as missing and created.

### Step 6 — Final report

After both skills have run, print:

1. The full file tree that was created.
2. The next manual steps:
   - `uv venv && source .venv/bin/activate && uv pip install dbt-core <DBT_ADAPTER> openlineage-dbt datacontract-cli entropy-data`
   - Copy `profiles.yml.example` to `~/.dbt/profiles.yml` and fill in credentials.
   - `git init && git add . && git commit -m "Initial commit"` (if not already a repo).
   - Create a GitHub repo and push; set the secrets called out by the integration skill (`ENTROPY_DATA_API_KEY`, platform creds).
   - Fill in the data contract schema in `datacontracts/`.

## Constraints

- **Do not run `dbt init`** — it generates an example layout that does not match the Entropy Data conventions. Use the templates here.
- **Do not commit secrets**. `profiles.yml` is in `.gitignore`; only `profiles.yml.example` is checked in.
- **Do not invent credentials**. Every secret in `profiles.yml.example` should be a `<fill in>` placeholder.
- **Idempotent on greenfield only**. If `dbt_project.yml` exists, route the user to `entropy-data-sync`; do not overwrite.
- **Do not run `git init`, `git commit`, or any push** — surface those as next steps for the user instead.
