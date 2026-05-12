---
name: dataproduct-design
description: Design a new data product before scaffolding — capture the business question, identify candidate input ports via the entropy-data CLI, decide grain and refresh cadence, draft the output-port data contract (columns, types, quality rules), and choose an owning team. Produces a draft `<id>.odps.yaml` and `datacontracts/<contract>.odcs.yaml` that `dataproduct-bootstrap` (or `entropy-data-sync` for an existing dbt project) can pick up. Trigger when the user asks to "design a new data product", "plan a data product", "what data product should we build for …", or wants help thinking through a data product before building it.
---

# Design a new data product

This skill answers the **what** before `dataproduct-bootstrap` answers the **how**. It ends when there's a draft ODPS + ODCS on disk, the team is chosen, and the user has confirmed the design — *not* when there's a dbt project. Bootstrap (or sync) takes it from there.

Use this when the user has a business question or use case but no clear shape for the data product yet. If the user already has a published Entropy Data data product they want to implement, use **`dataproduct-implement`** instead.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Step 0 — Pre-checks

- Confirm `entropy-data --version` is on PATH (install with `uv tool install entropy-data` if not) and `entropy-data connection test` succeeds. If the test fails, stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>`.
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

1. **Optional — explore semantic concepts first.** If the organization has a semantic ontology, the entities in the business question may map to first-class concepts. Run `entropy-data semantics namespaces list -o json` to see what's defined. For each likely namespace, run `entropy-data semantics search <namespace> "<term>" -o json` for the entities you extracted (e.g. `customer`, `account`, `subscription`, `usage`). Concept hits with `kind: entity` or `kind: metric` indicate agreed-on definitions; note the concept `id`s for later traceability. The CLI doesn't list which data products implement a concept — for that, open the concept in the Entropy Data web UI, or move on to step 2.
2. **Find candidate data products by text.** Run `entropy-data search query "<term>" -o json` for each entity. The response lists resources matching the term across name, description, and tags. Filter to `resourceType == "DataProduct"` if the search returned mixed types.
3. **Inspect each candidate.** For each promising hit, run `entropy-data dataproducts get <id> -o json` to read its output ports, owner team, and contract ids.

Show the user a short candidate table:

| Data product | Output port | Owner | Why relevant |
|---|---|---|---|
| `dp_account_master` | `accounts` | accounts-team | Source of truth for account identity |
| `dp_subscription_billing` | `mrr_monthly` | billing-team | Brings in MRR and renewal dates |
| `dp_support_tickets` | `tickets_open` | support-team | Open-incident counts |

Ask the user to **confirm or pick a subset**. For each chosen input port, note the data product id, output port id, and contract id; you'll wire these as `inputPorts` in the ODPS draft. Note whether the user already has access to each input port — Step 7 handles the access requests once the consumer data product's id is fixed.

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

Invoke the **`entropy-data-teams`** skill so the user can pick from registered teams. Use the returned team `id` as `team.name` in the ODPS draft.

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

### Step 7 — Request access to input ports

For each chosen input port where the user does **not** already have access, the new data product is the natural consumer. Issue the request only if `DATA_PRODUCT_ID` already exists on the platform — typically as an earlier `status: draft` registration, or from a re-run of this skill:

```
entropy-data dataproducts get <DATA_PRODUCT_ID> -o json
```

- **Exists (any status)** → request access immediately for each input port that needs it:

  ```
  entropy-data access request <input-data-product-id> <input-output-port-id> \
    --purpose "<reason this design needs the input>" \
    --consumer-dataproduct <DATA_PRODUCT_ID>
  ```

  Don't block on the outcome — the platform routes by the provider's policy (auto-approve or manual review).

- **404** → the consumer data product does not exist on Entropy Data yet. Defer the access requests. In Step 8's final report, list the exact commands the user should run **after** the first CI publish from the GitHub Actions workflow scaffolded by sync. Do not fall back to a team-scoped request.

### Step 8 — Hand off

Two paths depending on the working directory:

- **Empty directory (greenfield)** → invoke `dataproduct-bootstrap`, passing the captured parameters so it doesn't re-ask. Bootstrap will scaffold the dbt project around the ODPS already on disk.
- **Existing dbt project** → invoke `entropy-data-sync`. Sync will detect the new ODPS/ODCS files in its audit and wire up OpenLineage, GitHub Actions, and git connections.

The downstream skill is responsible for placing the dbt models, not this one.

If Step 7 deferred any access requests, include them verbatim in the final user-facing summary so they're easy to copy-paste after first publish.

## Constraints

- **Don't write SQL or implementation logic.** This skill produces specs only. Model bodies are TODOs that `dataproduct-implement` (or the user) fills in later.
- **Don't invent contract fields.** Every column must trace to either (a) an input-port field the user picked, (b) a primary-entity identifier, (c) a clearly-named derived metric, or (d) a standard system column.
- **Don't skip the entropy-data-teams lookup** — `team.name` should match a registered team unless the user explicitly opts out.
- **Don't run `dbt init` or scaffold dbt files.** That's `dataproduct-bootstrap`'s job; mixing the two confuses re-runs.
- **Don't commit the drafts.** Leave VCS state to the user; the next-skill handoff produces the rest of the project tree before any commit makes sense.
- **Read-only against the platform for discovery.** This skill calls `entropy-data search query`, `entropy-data dataproducts get`, and `entropy-data semantics search`. The only write it issues is `entropy-data access request` for input-port access — itself a request, not a publish. No `datacontracts put`, no `dataproducts put` — those happen via the workflow scaffolded later.
- **Idempotent**: re-running with the same answers should produce the same drafts (with a diff prompt if files already exist).
