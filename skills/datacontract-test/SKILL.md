---
name: datacontract-test
description: Run the Data Contract CLI (`datacontract test`) against one or more ODCS contracts under `datacontracts/` to verify the live data still conforms — schema, quality rules, and freshness. Trigger when the user asks to "test the data contracts", "verify the data product matches its contract", "are we still contract-conformant", or "run the contract tests".
---

# Test ODCS data contracts against the live server

Run the **Data Contract CLI** (`datacontract test`) against contracts in `datacontracts/` to check whether the data currently produced by the warehouse still matches the schema and quality rules declared in the contract.

## When to use this vs. other skills

- **You changed a contract and want to know if the edit breaks consumers** → use `datacontract-edit` (it edits, tests, *and* classifies the failure as breaking-or-not).
- **You want to verify existing contracts against current data, no edits** → this skill.
- **A CI run failed the contract test step** → this skill, to reproduce locally with `--logs`.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **datacontract-test**. I'll:
> 1. Pre-checks: confirm the `datacontract` CLI is on PATH and the server credentials are available.
> 2. Pick which contract(s) to test — defaults to all `datacontracts/*.odcs.yaml`.
> 3. Pick the server (defaults to `production` if the contract has one).
> 4. Run `datacontract test` per contract and capture the result.
> 5. Report pass/fail with per-rule detail; flag missing credentials separately from real failures.

Then proceed.

### Step 0 — Pre-checks

- Confirm `datacontract --version` is on PATH. If not, stop and tell the user to install it (e.g. `uv tool install 'datacontract-cli[all]'`).
- Confirm `datacontracts/` exists and contains at least one `*.odcs.yaml`. If not, stop and tell the user there's nothing to test.
- For each contract that will run, inspect its `servers` block and list the env vars the chosen server type needs (e.g. `DATACONTRACT_SNOWFLAKE_USERNAME` / `..._PASSWORD`, `DATACONTRACT_DATABRICKS_TOKEN`, `DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON`). If any are unset, surface the list to the user and ask whether to continue (the CLI will fail-fast on that server) or stop. Do not try to source credentials yourself.

### Step 1 — Select contracts

- If the user named a specific contract file or data product id, resolve to one file under `datacontracts/`.
- If they didn't, default to **all** `datacontracts/*.odcs.yaml` and list them so the user can narrow down before running.
- Remember the resolved list as `CONTRACTS`.

### Step 2 — Select the server

For each contract in `CONTRACTS`:

- If the contract has exactly one server, use it.
- If it has multiple, default to `production`. If `production` isn't defined, ask the user which one.
- Only pass `--server all` if the user explicitly asks to test every server.

### Step 3 — Run the test

For each contract:

```
datacontract test datacontracts/<file>.odcs.yaml --server <server> --logs
```

- `--logs` ensures per-rule failure detail is in stdout — without it the CLI only prints a summary.
- If the user asks for a persisted report (e.g. to attach to a PR), add `--output ./test-results/<contract>.xml --output-format junit`.
- If the user asks to publish results back to Entropy Data (matches the generated CI workflow), add `--publish $API/test-results` where `$API` is the Entropy Data host. Don't publish by default — it writes server-side state.
- Capture stdout and exit code per contract. Non-zero exit means at least one rule failed.

Run sequentially, not in parallel — the warehouse is the bottleneck and parallel runs muddy the log output.

### Step 4 — Report

End with this two-part recap. Use the shared `Status` enum (`created`, `updated`, `already present`, `deferred`, `skipped`); for this skill the relevant statuses are `passed`, `failed`, and `skipped` (missing creds).

**Part 1 — outcome table.** One row per contract tested.

| Contract | Server | Result | Failures | Details |
|---|---|---|---|---|
| `<contract-file>` | `<server>` | `passed` / `failed` / `skipped` | count or `—` | one line per failing rule (field + rule), or "missing env var: …" if skipped |

**Part 2 — next steps.** Bullet list, include only what applies:

- For each failed rule, surface the field and the violated check (e.g. `orders.order_id: not_null violated for 17 rows`). If the user wants a follow-up SQL to find the offending rows, suggest the shape but don't run it.
- For each `skipped` row, the exact env vars the user needs to set, and where to get them (usually the warehouse admin or `entropy-data connection get`).
- If failures look like they came from a contract edit (rules tightening), point at `datacontract-edit` to classify breaking-vs-additive.
- If failures look like a data quality issue (rules unchanged, data drifted), suggest investigating upstream — this skill does not auto-fix data.

If everything passed, write a single line: `All <N> contracts pass against <server>.`

## Constraints

- **Read-only against the warehouse.** This skill runs `datacontract test` which executes `SELECT` queries; it never writes. Do not invoke `datacontract publish`, `datacontract export`, or `entropy-data datacontracts put` from this skill.
- **No edits to contracts or models.** If a test fails, surface it — do not auto-patch the contract to make it pass. That defeats the purpose.
- **No credential sourcing.** If env vars are missing, tell the user; don't read them from `.env`, `~/.aws`, or anywhere else on the user's behalf.
- **Idempotent**: re-running the skill produces the same report against the same data. Failures from rules that depend on time (freshness, row-count windows) are expected to drift — note that in the failure detail when relevant.
