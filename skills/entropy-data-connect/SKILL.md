---
name: entropy-data-connect
description: Ensure an active Entropy Data CLI connection exists before running anything that touches the platform. Detects existing connections, validates them with `entropy-data connection test`, and walks the user through creating a user-scoped API key when none is found or the stored one is invalid. Triggered as Step 0 by every other skill that calls Entropy Data; can also be invoked directly when a user asks to "log in to Entropy Data", "connect to Entropy Data", or "set up my API key".
---

# Connect to Entropy Data

Make sure the `entropy-data` CLI has a working API-key connection to the user's Entropy Data organization. All other skills what interact with Entropy Data depend on this.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `settings.json`, `.mcp.json`, and `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}` — use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Step 0 — Pre-checks

- `entropy-data --version` is on PATH and reports **0.3.3 or later**.
  - If the CLI is missing: print `uv tool install entropy-data` and stop.
  - If the version is older: print `uv tool install --upgrade entropy-data` and stop.

### Step 1 — Try the existing connection

Run:

```
entropy-data connection test
```

- **Exit 0** → a default connection is set and works. Continue to Step 4 to print a confirmation. **Stop.**
- **Exit 2 (configuration error, no API key found)** → no connection configured. Go to Step 2.
- **Exit 1 with HTTP 401 / 403** → key is invalid (revoked, rotated, expired). Go to Step 2 with a one-line "your stored key is no longer valid" hint.
- **Other errors** (network, 5xx) → surface the error verbatim and stop. Don't drop into the setup flow on transient failures — it would discard a working connection.

If `connection test` succeeds but the user passed `--connection <name>` or asked you to use a non-default connection, run `entropy-data connection test -c <name>` instead and apply the same logic.

### Step 2 — Set up a user-scoped API key

**If `$ENTROPY_DATA_API_KEY` is already exported in the user's shell**, reuse it instead of asking the user to create a new key. Ask only for the host (the API key is opaque, the host is not):

> Found `ENTROPY_DATA_API_KEY` in your environment. What is your Entropy Data host (the URL from your browser's address bar after login, e.g. `https://acme.entropy-data.com`)? Default: `https://api.entropy-data.com`.

If `$ENTROPY_DATA_HOST` is also set, use that as the default instead of prompting.

Then run:

```
entropy-data connection add <name> --api-key "$ENTROPY_DATA_API_KEY" --host <host>
```

Use the variable reference literal (`$ENTROPY_DATA_API_KEY`), not the expanded value, so the key does not enter the transcript. Derive `<name>` from the host's first subdomain (see below). Continue to Step 3.

**Otherwise, walk the user through creating one.** Tell them, in this exact shape:

> To connect to Entropy Data, I need a user-scoped API key. Please:
>
> 1. Open Entropy Data in your browser and log in to your organization.
> 2. From your address bar after login, copy the URL — that's your **host** (e.g. `https://acme.entropy-data.com`).
> 3. In the web UI, go to **Organization Settings → API Keys → Create new API key**. Select as Scope `User (personal token)`. Copy the key.

Then ask for two values in **one** batched question:

| Prompt | What to capture | Default |
|---|---|---|
| `host` | The full URL from the address bar after login | none — must be provided |
| `api_key` | The key the user just copied | none — must be provided |

**Security**: there are two ways for the user to deliver the key. Recommend (a):

- **(a) Self-run** — print the exact command and ask the user to run it themselves in their terminal so the key never enters the agent transcript:

  ```
  entropy-data connection add <name> --host <host>
  ```

  The CLI will prompt for the API key interactively and accept it without echoing. Wait until the user confirms they ran it; then go to Step 3.

- **(b) Paste in chat** — the user pastes the key into the conversation. Less secure (the key lands in the agent transcript and any logs). Only use this if the user explicitly asks for the faster path. Then run the command yourself:

  ```
  entropy-data connection add <name> --api-key <pasted> --host <host>
  ```

In either case, derive `<name>` from the host's first subdomain (e.g. `acme.entropy-data.com` → `acme`); ask the user to confirm or override before running.

### Step 3 — Verify

Right after `connection add` completes, the CLI prints `Fetched organization vanity URL '<vanity>' from <host>.` if the auto-fetch succeeded. If it didn't print that line, the org-settings endpoint isn't available on this server (older deployment) — note it but continue.

Then run:

```
entropy-data connection test -c <name>
```

- **Exit 0** → continue to Step 4.
- **Exit 1 / 2** → surface the CLI error and the most likely cause:
  - `401`/`403` → the API key is wrong or scoped incorrectly (probably team-scoped, not user-scoped, or copied with whitespace). Offer to retry without re-pasting the host.
  - Network → the host URL is wrong or unreachable. Offer to retry.

If this is the only connection, run `entropy-data connection set-default <name>`. If there are others, leave the default alone unless the user asks to switch.

### Step 4 — Print a one-line confirmation

Run:

```
entropy-data organization get -o json
```

Parse and print:

```
Connected to <fullName> as '<vanityUrl>' (<host>).
```

Use the values from `fullName`, `vanityUrl`, and `host` in the response. If `entropy-data organization get` fails (older server without `/api/organization/settings`), fall back to:

```
Connected to <name> at <host>.
```

That's the success state. Other skills called above this one should now proceed.

## When other skills should call this

Every skill that shells out to `entropy-data` or hits the MCP server should run this skill **as Step 0** before doing anything else. If `entropy-data-connect` cannot establish a working connection, the calling skill aborts with the same error message — it does **not** retry, prompt for credentials itself, or fall back to env vars.

Skills that need it today:

- `dataproduct-bootstrap` (calls `dataproducts put` later via the workflow it scaffolds — but the skill itself doesn't hit the API; this is optional Step 0)
- `entropy-data-sync` (calls `gitconnection put`, list/get for audit)
- `dataproduct-implement` (MCP `fetch`, `datacontract_get`)
- `datacontract-edit` (`datacontract test` shells out to `datacontract` CLI, but ODCS may need MCP for upload)
- `dataproduct-exampledata-upload` (`example-data put`)
- `team-list` (`teams list`)

## MCP server auth — separate flow

This skill only handles the **CLI's** API key. The MCP server in `.mcp.json` authenticates separately via OAuth on first tool call (browser-based, one-time consent). That works today and does not require this skill.

If the user reports that an MCP tool call fails with an auth error, route them to `/mcp` (Claude Code) or the equivalent MCP-config command in their CLI to re-authenticate. Don't try to share the CLI's API key with the MCP server in this skill — that requires `.mcp.json` changes and shell env-var plumbing that isn't in scope here.

## Constraints

- **Never echo, log, or store the API key outside `~/.entropy-data/config.toml`.** That file is the CLI's source of truth (mode 0600). Don't write the key to env files, project `.env`, or print it back to the user as confirmation.
- **Don't run `entropy-data api-keys create`.** That command mints team-scoped keys and requires existing auth. The user must create the key in the web UI for now.
- **Don't auto-upgrade the CLI.** If the version is too old, surface the upgrade command and stop — let the user decide when to install software.
- **Don't loop on 401/403.** Two failed attempts is the limit; on a third, stop and tell the user to verify the key in the web UI.
- **Idempotent**: running this skill when a connection already works is a single `connection test` call that exits in milliseconds and prints the confirmation line.
