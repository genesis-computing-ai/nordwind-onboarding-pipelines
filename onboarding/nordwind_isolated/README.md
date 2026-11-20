# Isolated Nordwind one-shot rehearsal

This runtime-only dbt example adapts the already-public synthetic Nordwind
project at commit
[`be90ee896e2f7cc0c0bcf1e383f40bca1e413593`](https://github.com/genesis-computing-ai/nordwind-onboarding-pipelines/tree/be90ee896e2f7cc0c0bcf1e383f40bca1e413593/onboarding/nordwind_outdoor_3).
It preserves the order and order-line transformation expressions, contracts,
dependency, and grain tests. The source identifier is now a validated variable.
The inline CSV settings come from that commit's public file-format definition.

No input rows, credentials, deployment script, production target, recurring
task, or proof result is included. This example does not claim a completed
warehouse run or an independent onboarding proof.

## Required runtime configuration

Use a supported authenticated Snowflake dbt execution host. Authentication is
supplied by the host; never put credentials into this directory.

| Variable | Purpose |
| --- | --- |
| `DBT_DATABASE` | Existing development database; must end in `_DEV`. |
| `DBT_RUN_ID` | New random 8-24-character alphanumeric rehearsal ID. |
| `DBT_ROLE` | The execution host's already-authorized role, unchanged. |
| `DBT_WAREHOUSE` | The execution host's existing warehouse. |
| `DBT_SOURCE_STAGE` | Existing, fully qualified stage in that development database. No URL or path is accepted. |

The selected role must already be allowed to read the synthetic fixture and
create the rehearsal schemas and tables. This project never grants access or
changes the host's connection settings.

Both namespaces derive from the same required run ID:

- Raw: `NORDWIND_REHEARSAL_<RUN_ID>_RAW`
- Output: `NORDWIND_REHEARSAL_<RUN_ID>_OUT`

Before execution, independently verify that both namespaces are new and empty
and that the existing source stage exposes only the approved synthetic fixture.
Do not reuse a known-good schema or run this project against a production
database. A project object's location alone does not control dbt output.

## One-shot execution

Select the `rehearsal` profile target and run `dbt build` once with the
configuration above. The default fixture is the already-existing
`nordwind_orders_2026-10-24.csv`; `merchant.json` is never loaded. A
`fixture_file` variable may select another existing daily Nordwind CSV filename,
but directories and URLs are rejected.

The ORDERS pre-hooks create only the isolated raw schema and table, then copy
that single fixture with `FORCE = FALSE`. ORDER_LINES depends on ORDERS.
Incremental model and contract writes stay in the isolated output schema.
Full refresh, custom output databases/schemas, malformed identifiers, and
alternate time-zone semantics fail compilation. No task is created or enabled.

A successful `dbt build` checks the declared contracts and two grain tests.
That is warehouse validation, not the broader independent onboarding proof.
Report any fresh independent proof separately, with its own run identifier.
