---
name: sap-report-launcher
description: Runs SAP reports (by name or transaction, e.g. MB52, ZMMBE) with a variant and/or selection values without SAP GUI and reads their ALV output as JSON or the list as text, through the ARC-1 tool Custom_LaunchReport. Use it whenever the user wants to run a report, try out a result, compare the output of two reports or two versions of a report (e.g. original and Z copy), check a newly developed report with real data, or see what comes out "with variant X" or "for plant Y", even if the tool is not named. Not for dialog transactions (VA01, VA02...) or for reading tables (use SAPQuery for that).
---

# Running SAP reports without GUI

The tool `Custom_LaunchReport` does a `SUBMIT` of the report on the system, captures the ALV
(`CL_SALV_BS_RUNTIME_INFO`) and returns it as JSON; if the report produces a classic list, it
returns the text. If the tool is missing, the kit is not installed on this system: use the
skill `sap-arc1-kit`.

## When it is the right choice

- Checking what a report produces with some filters, or after a change.
- Comparing two reports (e.g. standard vs Z copy, old vs new version) on the same filters.
- Trying a saved variant.

Not suitable for: dialog transactions (refused), reports that open popups or `CALL SCREEN`,
reports that ask for confirmations. To simply read data from tables, `SAPQuery` is more direct.

## Before running

1. **Does the report change data?** If the report updates data (batch input, write BAPIs,
   `UPDATE`/`INSERT`, "update run"), ask the user for confirmation before running it.
   When in doubt read the source (`SAPRead` with `grep` on `COMMIT|UPDATE|INSERT|MODIFY|BAPI`).
2. **Selection field names**: they are the names of the report `PARAMETERS` / `SELECT-OPTIONS`
   (max 8 characters), not table field names. Find them with
   `SAPRead type=PROG name=<report> grep="PARAMETERS|SELECT-OPTIONS"`. For standard
   transactions (e.g. MB52 → `RM07MLBS`) the report is the one resolved from the transaction.
3. **Variants**: they are client-specific. List them with
   `SAPQuery: SELECT variant FROM varid WHERE report = '<REPORT>'`. The content of a variant is
   often not readable via ADT: if you need to know what it filters, ask the user or compare the
   result with a run with explicit values.
4. **Volume**: start with narrow filters. `maxRows` limits the returned rows (default 200),
   but the report still processes everything: a report without filters on large tables can
   run for minutes and hit the ADT timeout (e.g. MB52 without material or plant reads the whole
   stock). Always pass at least one key filter such as material or plant. Show the user only
   what is needed, especially with personal data.

## Tool parameters

| Field | Notes |
|---|---|
| `report` or `tcode` | One of the two. `tcode` must be a report transaction |
| `variant` | Optional; the `params` passed override the variant values |
| `params[]` | `name`, `kind` (`P` parameter / `S` select-option), `sign` (`I`/`E`), `option` (`EQ`, `BT`, `CP`, ...), `low`, `high` |
| `maxRows` | Rows returned (1–5000) |

Values always in **SAP internal format**: dates `YYYYMMDD`, flags `X`, document and material
numbers with leading zeros if the field needs them (e.g. `0080012345`), patterns with `*` and
`option: CP`. Several rows with the same `name` = several values of the same select-option.

Example: stock of plant 1001, storage locations M001 to M003, materials starting with 1000:
```json
{ "tcode": "MB52",
  "params": [
    { "name": "WERKS", "kind": "S", "low": "1001" },
    { "name": "LGORT", "kind": "S", "option": "BT", "low": "M001", "high": "M003" },
    { "name": "MATNR", "kind": "S", "option": "CP", "low": "1000*" } ],
  "maxRows": 50 }
```

## Reading and comparing the results

- The header shows report, variant, output type (`ALV`, `LIST` or none) and number of rows.
  "No output" usually means the selection is empty or the report only showed a message.
- ALV columns have the technical field names of the report's internal table.
- To compare two reports: same `params` on both, then compare row counts and totals per key.
  With more than a few dozen rows, save the two JSON outputs to a file and compare them with a
  script instead of by eye.
- Report to the user: filters used, rows found, differences, and a minimal sample of rows.

## Typical errors

| Message | Meaning |
|---|---|
| "is not an executable report" | Module pool / dialog transaction: cannot be run |
| "Variant ... does not exist ... in client" | Wrong name or variant of another client |
| HTTP 500 from SOAP-RFC | The report issued a `MESSAGE` of type E/A (e.g. "no data"): review the filters |
| "No authorization for transaction" | The user lacks the `S_TCODE` authorization |
