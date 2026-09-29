---
name: sap-arc1-kit
description: Installs on an SAP system (on-premise, through the ARC-1 MCP server) the tool kit that lets Claude run reports with variants/selection values and read the ALV output, create PDF previews of NAST print output, read and edit SmartForms as XML, and replace a customer form with the approved copy. Use it when starting a new SAP project and the tools Custom_LaunchReport, Custom_PrintPreview, Custom_SmartFormRead/Write/Replace are not available, when the user asks to "install/port the tools", "prepare the system", "set up the report launcher or SmartForms tools" on a new system or client, or when the skills sap-report-launcher / sap-smartform-xml report that the tools are missing.
---

# ARC-1 kit: installation on a new SAP system

The kit has two parts that are installed together:

| Part | Where | Content (default prefix `ZAI`) |
|---|---|---|
| ABAP | SAP system | 3 exception classes, 3 logic classes, function group `ZAI_FG_LAUNCHER` with 6 function modules (5 remote-enabled) |
| ARC-1 extension | PC, project folder | 5 MCP tools: `Custom_LaunchReport`, `Custom_PrintPreview`, `Custom_SmartFormRead`, `Custom_SmartFormWrite`, `Custom_SmartFormReplace` |

The tools call the function modules through the standard SOAP-RFC service (`/sap/bc/soap/rfc`),
because ARC-1 extensions can only make HTTP calls.

The sources are in `assets/` (`abap/clas`, `abap/fugr`, `arc1-extension`). They need
SAP_BASIS 7.50 or later: ECC 6.0 EHP8 and every S/4HANA on-premise / private cloud release.
They were tested live on S/4HANA 2025 (SAP_BASIS 816) and ECC 6.0 EHP8 (SAP_BASIS 750); they avoid
newer constructs on purpose (`RAISE EXCEPTION TYPE`, POSIX `REGEX` instead of `NEW` and PCRE).
On ECC check before installing that the class `/UI2/CL_JSON` exists (used for the ALV output).

## Before starting: what to ask or check

1. **Project rules**: read the project `CLAUDE.md`. It decides package, prefix and whether
   transport requests are needed. On a customer system do not create transport requests or
   transportable packages without explicit confirmation from the user.
2. **Object prefix**: generic, never personal (default `ZAI`). If the project has a different
   naming convention, ask the user for the prefix. Max 10 characters, starting with Z or Y.
3. **Package**: `$TMP` on development/sandbox systems; a project package only if the user asks
   for it (it needs a transport request).
4. **ARC-1 configured** in `.mcp.json` with writes enabled (`SAP_ALLOW_WRITES=true`) and the
   target package in `SAP_ALLOWED_PACKAGES`.
5. **SICF service `/sap/bc/soap/rfc` active** (transaction `SICF`). Claude cannot activate it:
   if it is inactive, ask the user or the Basis team. Quick check: the first tool call returns
   HTTP 403/404 if the service is off.
6. **SAP user authorizations**: `S_RFC` on the function group, plus those needed to run the
   reports and read spool requests.

## Step 1 — Prepare the sources with the chosen prefix

```bash
python <skill>/scripts/set_prefix.py --to ZAI --dest <project>/sap-kit
```

The script copies `assets/` and replaces the prefix in file names and content
(ABAP and TypeScript), upper and lower case. With `--to ZAI` it only copies.

## Step 2 — ABAP objects (order matters)

Use `SAPWrite` with the chosen `package` (and `transport` if not `$TMP`). Read each file and
pass its content unchanged.

1. **Exception classes** `<P>_CX_LAUNCHER`, `<P>_CX_PRINT_PREVIEW`, `<P>_CX_SMARTFORM`
   → `SAPWrite batch_create` with `activateAtEnd: true`.
2. **Function group** `<P>_FG_LAUNCHER` → `SAPWrite create type=FUGR`.
3. **Include** `L<P>_FG_LAUNCHERF01` (work areas `TABLES: nast, tnapr`) →
   `SAPWrite create type=INCL group=<P>_FG_LAUNCHER`. ARC-1 adds the `INCLUDE` line to the
   main program by itself.
4. **FM** `<P>_PRINT_CALL_ROUTINE` → `type=FUNC`, `processingType: normal`.
5. **Classes** `<P>_CL_REPORT_LAUNCHER`, `<P>_CL_PRINT_PREVIEW`, `<P>_CL_SMARTFORM_XML`
   (files `.clas.abap`) → `SAPWrite create type=CLAS`.
6. **Remote-enabled FMs** `<P>_RUN_REPORT`, `<P>_RUN_PRINT_PREVIEW`, `<P>_SMARTFORM_READ`,
   `<P>_SMARTFORM_WRITE`, `<P>_SMARTFORM_REPLACE` → `type=FUNC`, `processingType: rfc`.
7. **One activation** with `SAPActivate objects=[...]` of: the 3 classes, the include, the 6 FUNC
   (with `group`) and the FUGR. New FMs stay inactive if only the FUGR is activated: they must
   be listed explicitly.
8. **Tests** (`.testclasses.abap`) → `SAPWrite update include=testclasses` for each class,
   then `SAPActivate` of the 3 classes.

## Step 3 — Checks on the system

- `SAPQuery`: `SELECT funcname, fmode FROM tfdir WHERE funcname LIKE '<P>_%'` → the 5 entry
  FMs with `FMODE = 'R'`, `<P>_PRINT_CALL_ROUTINE` empty.
- `SAPDiagnose unittest` on the 3 classes: 8 + 8 + 14 tests, no errors. Tests that find no
  suitable data on the system end with a **tolerable** assertion (`CL_ABAP_UNIT_ASSERT=>SKIP`
  does not exist on 7.50): ARC-1 then reports the class as `failed` with `severity: tolerable`.
  This is expected, not a problem, when the message says what is missing:
  "No BA00 message in this system", "No preview spool request below the TSP01 maximum" (normal
  before the first `Custom_PrintPreview` on the system), "Output type V1/ZZZZ has a TNAPR entry
  in this system", "No transportable Z*/Y* SmartForms of other users or no open request". Any other failure, or a `critical` one, is a real error.
- `SAPDiagnose atc`: no priority 1/2 findings. Priority 3 findings on "texts without text
  element" are accepted (technical messages) unless the project rules say otherwise.
- `Custom_SmartFormReplace` is tried only on a test Z form, in a transportable package and
  with a transport request given by the user (tested on S/4HANA 2025: `prepare` + `execute`
  successful, form recorded in the request without popup via RFC).
  There is no need to repeat the test on every system: a `prepare` and the user's confirmation
  before the first real `execute` are enough.

## Step 4 — ARC-1 extension

1. Copy `sap-kit/arc1-extension` into the project folder (e.g. `<project>/arc1-extension`).
2. `npm install --ignore-scripts`, then `npm test` (builds into `dist/` and runs 20 Node tests).
   `--ignore-scripts` skips the native build of ARC-1 dependencies, which the extension does
   not need.
3. In `.mcp.json`, in the ARC-1 server, add to `env`:
   ```json
   "ARC1_PLUGINS": "<absolute path>/arc1-extension/dist/index.js",
   "SAP_ALLOW_PLUGIN_RAW_WRITES": "true"
   ```
   The second flag is needed because the tools make HTTP POST calls to SAP.

   Rules for `Custom_SmartFormReplace`, in the same `env` (the variable names follow the
   chosen prefix, e.g. `ZXYZ_CHECK_AUTHOR`):

   | Variable | Use | Default |
   |---|---|---|
   | `SAP_ALLOW_TRANSPORT_WRITES` | Must be `true`, otherwise the tool refuses | - |
   | `SAP_ALLOWED_PACKAGES` | Packages in which an original can be replaced | empty = none |
   | `<P>_CHECK_AUTHOR` | Check done in ABAP with the user actually logged on (`sy-uname`); `false` on systems with a shared SAP user, where the author does not tell who wrote the form | `true` |
   | `<P>_ALLOWED_TRANSPORTS` | Allowed transport requests, comma separated | all modifiable workbench requests |
4. Ask the user to **restart Claude Code** (or reconnect the ARC-1 server): the tools appear
   only afterwards. Then `ToolSearch` with `Custom_` to check them.

## Step 5 — Quick test

- `Custom_LaunchReport` with `tcode: "MB52"` (or a Z report of the project) and a narrow filter.
- `Custom_SmartFormRead` on `LE_SHP_DELNOTE` or a project form → XML saved.
- `Custom_PrintPreview` on a document with a NAST print message → PDF saved.

Then record prefix, package, created objects and results in the project notes.

## Known problems

| Symptom | Cause / fix |
|---|---|
| HTTP 403/404 from `/sap/bc/soap/rfc` | SICF service inactive or user without authorization |
| SOAP fault "function not found" | FM inactive or not remote-enabled (`FMODE`) |
| FMs created but inactive after activating the FUGR | Activate them explicitly as FUNC with `group` |
| `Custom_*` tools missing | Extension not built, wrong `ARC1_PLUGINS` path or Claude Code not restarted |
| After a prefix change the tools call FMs that do not exist | Rebuild the extension (`npm test`) from the copy with the new prefix |

To use the tools: skills `sap-report-launcher` and `sap-smartform-xml`.
