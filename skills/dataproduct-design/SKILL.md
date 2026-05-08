---
name: dataproduct-design
description: Design a new data product before scaffolding — capture the business question, identify candidate input ports via the Entropy Data MCP, decide grain and refresh cadence, draft the output-port data contract (columns, types, quality rules), and choose an owning team. Produces a draft `<id>.odps.yaml` and `datacontracts/<contract>.odcs.yaml` that `dataproduct-bootstrap` (or `entropy-data-sync` for an existing dbt project) can pick up. Trigger when the user asks to "design a new data product", "plan a data product", "what data product should we build for …", or wants help thinking through a data product before building it.
---

# Design a new data product

This skill answers the **what** before `dataproduct-bootstrap` answers the **how**. It ends when there's a draft ODPS + ODCS on disk, the team is chosen, and the user has confirmed the design — *not* when there's a dbt project. Bootstrap (or sync) takes it from there.

Use this when the user has a business question or use case but no clear shape for the data product yet. If the user already has a published Entropy Data data product they want to implement, use **`dataproduct-implement`** instead.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `settings.json`, `.mcp.json`, and `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Step 0 — Pre-checks

- Run `entropy-data-connect` so MCP/CLI calls in later steps work. Abort if it fails.
- Confirm the working directory is either empty (greenfield) or already a dbt project (`dbt_project.yml` exists). If neither, ask the user where they want the design to land.

### Step 1 — Capture the business question

Ask the user, in one batched prompt, for:

| Field | What to capture | Example |
|---|---|---|
| `BUSINESS_QUESTION` | One sentence describing the question this data product answers | "Which customer accounts are at risk of churn next quarter?" |
| `PRIMARY_CONSUMER` | Team / role that will use it | "Customer Success" |
| `DECISIONS_DRIVEN` | One or two decisions the consumer will make from this data | "Prioritize renewal outreach; assign CSMs to at-risk accounts" |
| `BUSINESS_DOMAIN` | Domain or use-case slug | "customer-success" |

Reject vague answers (*"general analytics"*) — push back once with a specific question (*"what decision will be made from it?"*) before accepting.

### Step 2 — Identify candidate input ports

Discover existing data products that could feed this one:

1. Call MCP `search` with terms derived from the business question (entities like `customer`, `account`, `subscription`, `usage`).
2. For each promising hit, call `fetch` to read its output ports, owner team, and contract summary.
3. Optionally call `semantics_search_concepts` / `semantics_find_data_products_for_concept` for ontology-level matches.

Show the user a short candidate table:

| Data product | Output port | Owner | Why relevant |
|---|---|---|---|
| `dp_account_master` | `accounts` | accounts-team | Source of truth for account identity |
| `dp_subscription_billing` | `mrr_monthly` | billing-team | Brings in MRR and renewal dates |
| `dp_support_tickets` | `tickets_open` | support-team | Open-incident counts |

Ask the user to **confirm or pick a subset**. For each chosen input port, note the data product id, output port id, and contract id; you'll wire these as `inputPorts` in the ODPS draft. If the user does not have access to a chosen input port, run `request_access` via MCP — but don't block; access can resolve in parallel.

### Step 3 — Decide grain, cadence, primary entity

Walk the user through:

| Decision | Question to ask |
|---|---|
| `PRIMARY_ENTITY` | "What does one row in the output represent?" (e.g. one account, one account-month, one event) |
| `GRAIN` | The entity + period (e.g. "one row per account per month") — must be unambiguous |
| `REFRESH_CADENCE` | "How fresh does the data need to be?" (`hourly`, `daily`, `weekly`, `on-demand`) |
| `RETENTION` | "How much history do consumers need?" (`90 days`, `2 years`, `all-time`) |
| `EXPECTED_VOLUME` | Order of magnitude of rows (informs warehouse sizing later) |

These decisions shape the contract's primary key, partitioning, and update strategy.

### Step 4 — Draft the output-port contract

Build the ODCS columns from:

1. The `PRIMARY_ENTITY`'s identifier(s) (the natural primary key).
2. Columns from the chosen input ports that the `BUSINESS_QUESTION` requires — ask the user to pick from each input port's `models[].fields[]`. Don't invent fields.
3. Derived metrics implied by the question (e.g. `churn_risk_score`, `mrr_total`, `last_interaction_date`). Mark these as TODO with a comment — actual SQL is `dataproduct-implement`'s job, not this skill's.
4. Standard system columns: `updated_at` (timestamp the row was last refreshed), and a stable `id` if one isn't already present from (1).

For each column, decide:

- `type` (string, integer, decimal, timestamp, date, boolean) — keep it warehouse-neutral
- `required` (true if every row must have a value)
- `unique` (true if it's a PK component)
- `classification` (`public` / `internal` / `pii` / `confidential` / `restricted`) — important for downstream consumers (and for `dataproduct-exampledata-upload`'s scrub plan)
- `description` (one short sentence — it's the consumer's first encounter with the column)

Add **quality rules** the consumer will rely on: row-count thresholds, freshness windows, referential checks against input ports. Two or three is enough; don't over-engineer.

### Step 5 — Choose the owning team

Invoke the **`team-list`** skill so the user can pick from registered teams. Use the returned team `id` as `team.name` in the ODPS draft.

If the user explicitly wants a free-text owner (e.g. an external consultancy that isn't in Entropy Data), accept the string but warn that team-scoped views in the UI will not include this data product.

### Step 6 — Compute the data product id and persist the drafts

Compute these from the captured fields (no second prompt):

| Field | Default formula |
|---|---|
| `DATA_PRODUCT_ID` | `dp_<business_domain>_<primary_entity>` (e.g. `dp_customer_success_account_health`) — show to user, allow rename |
| `DATA_PRODUCT_NAME` | Title-cased phrase from the entity (e.g. `Account Health`) |
| `OUTPUT_PORT_ID` | the table name from Step 4's contract |
| `CONTRACT_ID` | `<DATA_PRODUCT_ID>-v1` |

Write two files (do **not** overwrite existing files; if either exists, surface the diff and ask):

1. `<DATA_PRODUCT_ID>.odps.yaml` — the ODPS draft. Use `${PLUGIN_ROOT}/skills/entropy-data-sync/templates/data-product.odps.yaml` as the starting shape and substitute the captured fields. Include a `domain:` and a `tags:` entry for traceability.
2. `datacontracts/<CONTRACT_ID>.odcs.yaml` — the ODCS draft with the columns from Step 4. Use `${PLUGIN_ROOT}/skills/entropy-data-sync/templates/datacontracts/contract.odcs.yaml` as the starting shape.

Show the file paths and a quick summary table (data product id, output port, owner, primary key, refresh cadence, classifications-of-concern). Wait for the user to confirm.

### Step 7 — Hand off

Two paths depending on the working directory:

- **Empty directory (greenfield)** → invoke `dataproduct-bootstrap`, passing the captured parameters so it doesn't re-ask. Bootstrap will scaffold the dbt project around the ODPS already on disk.
- **Existing dbt project** → invoke `entropy-data-sync`. Sync will detect the new ODPS/ODCS files in its audit and wire up OpenLineage, GitHub Actions, and git connections.

The downstream skill is responsible for placing the dbt models, not this one.

## Constraints

- **Don't write SQL or implementation logic.** This skill produces specs only. Model bodies are TODOs that `dataproduct-implement` (or the user) fills in later.
- **Don't invent contract fields.** Every column must trace to either (a) an input-port field the user picked, (b) a primary-entity identifier, (c) a clearly-named derived metric, or (d) a standard system column.
- **Don't skip the team-list lookup** — `team.name` should match a registered team unless the user explicitly opts out.
- **Don't run `dbt init` or scaffold dbt files.** That's `dataproduct-bootstrap`'s job; mixing the two confuses re-runs.
- **Don't commit the drafts.** Leave VCS state to the user; the next-skill handoff produces the rest of the project tree before any commit makes sense.
- **Read-only against the platform.** This skill calls MCP `search`/`fetch`/`semantics_*` and at most `request_access`. No `datacontract_save`, no `dataproducts put` — those happen via the workflow scaffolded later.
- **Idempotent**: re-running with the same answers should produce the same drafts (with a diff prompt if files already exist).
