---
name: datacontract-edit
description: Edit an Open Data Contract Standard (ODCS) file in datacontracts/, run the contract test against the live data, and classify any failures as breaking or non-breaking changes — with suggested fixes. Trigger when the user asks to "add/remove/change a column in the data contract", "update the data contract", or "test contract changes".
---

# Edit a data contract and test the impact

Change a `datacontracts/*.odcs.yaml` file, run the contract test, and tell the user whether the change breaks consumers.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Step 0 — Locate the contract

- If the user named a contract file or column, find the matching file under `datacontracts/`.
- If multiple contracts exist and it's ambiguous, list them and ask which one.
- Read the file and remember the current `models` block as `BEFORE`.

### Step 1 — Apply the edit

Edit the ODCS YAML in place using the user's instruction. Keep the change minimal — do not reformat unrelated fields.

Common edits and the right shape:

| User says | What to change |
|---|---|
| "add column X" | Append a field under the relevant model with at least `type`; set `required: false` by default unless the user says it's required |
| "remove column X" | Delete the field; this is **breaking** — flag in Step 4 |
| "rename X to Y" | Rename the field; this is **breaking** — flag |
| "make X required" | Add `required: true`; **breaking** if existing rows can be null |
| "change X type from int to string" | Update `type`; **breaking** unless the new type is a strict superset (e.g. int → bigint) |
| "add a unique/not_null/enum check" | Add to the field's quality rules; breaking iff existing data violates the new rule — only Step 2 can tell |

After editing, remember the new `models` block as `AFTER` and show the user a unified diff before continuing.

### Step 2 — Run the contract test

Run the test with the **`datacontract` CLI** against the local contract file:

```
datacontract test datacontracts/<file>.odcs.yaml --server <server> --logs
```

- If the contract has more than one server, ask which one (typically `production`). Default to `all` only if the user explicitly asks.
- Use `--logs` so failure detail is in the output you read; otherwise the CLI only prints a summary.
- If the user wants the report persisted, add `--output ./test-results/junit.xml --output-format junit`.
- Capture stdout + exit code as `TEST_RESULT`. Non-zero exit means at least one rule failed; the log section names the failing field/rule.

Pre-reqs the CLI needs (verify before running, fail fast with a clear message if missing):

- `datacontract` on PATH (`datacontract --version`).
- The chosen server's credentials available as env vars per the ODCS server block (e.g. `DATACONTRACT_SNOWFLAKE_USERNAME` / `..._PASSWORD`, or `DATACONTRACT_DATABRICKS_TOKEN`). Tell the user which env vars are missing — do not try to source them yourself.

Do **not** use the platform's server-side contract-test endpoint from this skill. The local `datacontract` CLI runs against the edited file and gives line-level failure detail; testing the published version on the server would test the *previous* contract, which defeats the point of testing the edit.

### Step 3 — Classify the outcome

Group every failure into one of these buckets:

| Bucket | Examples | Severity |
|---|---|---|
| **Breaking — schema** | column removed, type narrowed, column renamed | High — bump major version, deprecate old port |
| **Breaking — quality** | new `not_null`/`unique`/`enum` rule violated by existing data | High — clean data first, then re-test |
| **Non-breaking — additive** | new optional column, widened type, loosened rule | Low — minor version bump |
| **Test failure unrelated to the edit** | flaky source, infra error, unchanged rule failing | Investigate separately |

For each failure, name the exact field/rule and which bucket it falls into. Don't lump them together.

### Step 4 — Report and suggest fixes

Print:

1. The diff applied in Step 1.
2. The classification table from Step 3, with one row per failure.
3. Concrete fix suggestions per failure:
   - **Schema breaking**: bump to a new output port version (`models/output_ports/v2/`), keep v1 alive, add a deprecation note in `<id>.odps.yaml`.
   - **Quality breaking**: a SQL snippet to find the offending rows in the source so the user can decide whether to clean, accept, or relax the rule.
   - **Additive**: bump the contract's `version` minor, no consumer impact.
4. If there are no failures, just say so and recommend the version bump (patch for cosmetic, minor for additive, major for breaking even if the test happened to pass).

**Do not auto-bump the contract version, do not create v2/ directories, and do not modify dbt models.** Surface the recommendation; let the user decide.

## Constraints

- **Always run the test after every edit.** A passing edit looks the same as a breaking edit until you run it.
- **Don't edit the dbt models in this skill.** Changing the contract is a separate decision from changing the implementation. If the user wants both, run `dataproduct-implement` after this skill.
- **Don't fetch a remote version of the contract** — operate on the local file. If the user wants to pull the published version, ask them to do that explicitly first (it can be a one-line `entropy-data datacontracts get <id> -o json` redirected to the file).
- **Idempotent**: re-running with the same edit should be a no-op (same diff = empty, same test = same result).
