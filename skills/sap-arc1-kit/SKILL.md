---
name: sap-arc1-kit
description: Installs on an SAP system (on-premise, through the ARC-1 MCP server) the tool kit that lets Claude run reports with variants/selection values and read the ALV output, create PDF previews of NAST print output, read and edit SmartForms as XML, replace a customer form with the approved copy, read and copy Adobe forms (SFP) as XML + XDP with their form interfaces, and give a customer Adobe form the layout of the approved copy. Use it when starting a new SAP project and the tools Custom_LaunchReport, Custom_PrintPreview, Custom_SmartFormRead/Write/Replace, Custom_AdobeFormRead/Write/Replace, Custom_AdobeInterfaceWrite are not available, when the user asks to "install/port the tools", "prepare the system", "set up the report launcher or SmartForms tools" on a new system or client, or when the skills sap-report-launcher / sap-smartform-xml / sap-adobe-form report that the tools are missing.
---

# ARC-1 kit: installation on a new SAP system

The kit has two parts that are installed together:

| Part | Where | Content (default prefix `ZAI`) |
|---|---|---|
| ABAP | SAP system | 4 exception classes, 4 logic classes, function group `ZAI_FG_LAUNCHER` with 10 function modules (9 remote-enabled) |
| ARC-1 extension | PC, project folder | 9 MCP tools: `Custom_LaunchReport`, `Custom_PrintPreview`, `Custom_SmartFormRead`, `Custom_SmartFormWrite`, `Custom_SmartFormReplace`, `Custom_AdobeFormRead`, `Custom_AdobeFormWrite`, `Custom_AdobeInterfaceWrite`, `Custom_AdobeFormReplace` |

The tools call the function modules through the standard SOAP-RFC service (`/sap/bc/soap/rfc`),
because ARC-1 extensions can only make HTTP calls.

The sources are in `assets/` (`abap/clas`, `abap/fugr`, `arc1-extension`). They need
SAP_BASIS 7.50 or later: ECC 6.0 EHP8 and every S/4HANA on-premise / private cloud release.
They avoid newer constructs on purpose (`RAISE EXCEPTION TYPE`, POSIX `REGEX` instead of `NEW` and PCRE).
On ECC check before installing that the class `/UI2/CL_JSON` exists (used for the ALV output).

ARC-1 tools are named here by their short name (`SAPWrite`, `SAPActivate`, `SAPQuery`,
`SAPDiagnose`); in Claude Code they are `mcp__<server>__<tool>`, where `<server>` is the name of
the ARC-1 server in `.mcp.json` (e.g. `mcp__arc1__SAPWrite`). If several ARC-1 servers are
configured, use the one of the target system and never a test or production one.

Copy this checklist into your answer and tick it off as you go:

```
Kit installation:
- [ ] Before starting: rules, prefix, package, ARC-1 writes, SICF, authorizations
- [ ] Step 1: sources prepared with the prefix
- [ ] Step 2: ABAP objects created, activated (FMs listed explicitly), tests uploaded
- [ ] Step 3: TFDIR, ABAP Unit, ATC checked
- [ ] Step 4: extension built and tested, .mcp.json updated, Claude Code restarted
- [ ] Step 5: quick test of the tools
```

## Before starting: what to ask or check

1. **Project rules**: read the project `CLAUDE.md`. It decides package, prefix and whether
   transport requests are needed. On a customer system do not create transport requests or
   transportable packages without explicit confirmation from the user.
2. **Object prefix**: generic, never personal (default `ZAI`). If the project has a different
   naming convention, ask the user for the prefix. Max 8 characters, starting with Z or Y.
3. **Package**: `$TMP` on development/sandbox systems; a project package only if the user asks
   for it (it needs a transport request).
4. **ARC-1 configured** in `.mcp.json` with writes enabled (`SAP_ALLOW_WRITES=true`) and the
   target package in `SAP_ALLOWED_PACKAGES`.
5. **SICF service `/sap/bc/soap/rfc` active** (transaction `SICF`). Claude cannot activate it:
   if it is inactive, ask the user or the Basis team. Quick check: the first tool call returns
   HTTP 403/404 if the service is off.
6. **SAP user authorizations**: `S_RFC` on the function group, plus those needed to run the
   reports and read spool requests.
7. **Adobe Document Services (ADS)**, only for the Adobe forms tools: without ADS they read forms
   but do not write them, and Adobe print output cannot be previewed. Manual check: report `FP_TEST_00`.

## Step 1 — Prepare the sources with the chosen prefix

```bash
python "${CLAUDE_SKILL_DIR}/scripts/set_prefix.py" --to ZAI --dest <project>/sap-kit
```

The script (Python 3, standard library only) copies `assets/` and replaces the prefix in file
names and content (ABAP and TypeScript), upper and lower case. With `--to ZAI` it only copies.
It refuses a prefix that does not start with Z/Y or is longer than 8 characters, and a target
folder that is not empty.

## Step 2 — ABAP objects (order matters)

Use `SAPWrite` with the chosen `package` (and `transport` if not `$TMP`). Read each file and
pass its content unchanged.

1. **Exception classes** `<PREFIX>_CX_LAUNCHER`, `<PREFIX>_CX_PRINT_PREVIEW`, `<PREFIX>_CX_SMARTFORM`,
   `<PREFIX>_CX_ADOBE_FORM`
   → `SAPWrite batch_create` with `activateAtEnd: true`.
2. **Function group** `<PREFIX>_FG_LAUNCHER` → `SAPWrite create type=FUGR`.
3. **Include** `L<PREFIX>_FG_LAUNCHERF01` (work areas `TABLES: nast, tnapr`) →
   `SAPWrite create type=INCL group=<PREFIX>_FG_LAUNCHER`. ARC-1 adds the `INCLUDE` line to the
   main program by itself.
4. **FM** `<PREFIX>_PRINT_CALL_ROUTINE` → `type=FUNC`, `processingType: normal`.
5. **Classes** `<PREFIX>_CL_REPORT_LAUNCHER`, `<PREFIX>_CL_PRINT_PREVIEW`, `<PREFIX>_CL_SMARTFORM_XML`,
   `<PREFIX>_CL_ADOBE_FORM` (files `.clas.abap`) → `SAPWrite create type=CLAS`.
6. **Remote-enabled FMs** `<PREFIX>_RUN_REPORT`, `<PREFIX>_RUN_PRINT_PREVIEW`, `<PREFIX>_SMARTFORM_READ`,
   `<PREFIX>_SMARTFORM_WRITE`, `<PREFIX>_SMARTFORM_REPLACE`, `<PREFIX>_ADOBE_FORM_READ`,
   `<PREFIX>_ADOBE_FORM_WRITE`, `<PREFIX>_ADOBE_INTERFACE_WRITE`, `<PREFIX>_ADOBE_FORM_REPLACE` → `type=FUNC`,
   `processingType: rfc`.
7. **One activation** with `SAPActivate objects=[...]` of: the 4 classes, the include, the 10 FUNC
   (with `group`) and the FUGR. New FMs stay inactive if only the FUGR is activated: they must
   be listed explicitly.
8. **Tests** (`.testclasses.abap`) → `SAPWrite update include=testclasses` for each class,
   then `SAPActivate` of the 4 classes.

## Step 3 — Checks on the system

- `SAPQuery`: `SELECT funcname, fmode FROM tfdir WHERE funcname LIKE '<PREFIX>_%'` → the 9 entry
  FMs with `FMODE = 'R'`, `<PREFIX>_PRINT_CALL_ROUTINE` empty.
- `SAPDiagnose unittest` on the 4 classes: 8 (report launcher) + 10 (print preview) + 14 (SmartForms)
  + 22 (Adobe forms) tests, no errors. Tests that find no
  suitable data on the system end with a **tolerable** assertion (`CL_ABAP_UNIT_ASSERT=>SKIP`
  does not exist on 7.50): ARC-1 then reports the class as `failed` with `severity: tolerable`.
  This is expected, not a problem, when the message says what is missing:
  "No BA00 message in this system", "No preview spool request below the TSP01 maximum" (normal
  before the first `Custom_PrintPreview` on the system), "Output type V1/ZZZZ has a TNAPR entry
  in this system", "No transportable Z*/Y* SmartForms of other users or no open request",
  "Standard Adobe form FP_TEST_00 not found in this system", "ADS not available in this system: ..."
  (the Adobe forms tools then only read), "No open task in this system", "No transportable Z*/Y*
  Adobe forms of other users or no open request". Any other failure, or a `critical` one, is a real error.
- `SAPDiagnose atc`: no priority 1/2 findings. Priority 3 findings on "texts without text
  element" are accepted (technical messages) unless the project rules say otherwise.
- `Custom_SmartFormReplace` and `Custom_AdobeFormReplace` are not tested at installation: before their
  first real `execute` on a system, a `prepare` and the user's explicit confirmation are enough.

## Step 4 — ARC-1 extension

1. Copy `sap-kit/arc1-extension` into the project folder (e.g. `<project>/arc1-extension`).
2. `npm install --ignore-scripts`, then `npm test` (builds into `dist/` and runs 35 Node tests).
   `--ignore-scripts` skips the native build of ARC-1 dependencies, which the extension does
   not need.
3. In `.mcp.json`, in the ARC-1 server, add to `env`:
   ```json
   "ARC1_PLUGINS": "<absolute path>/arc1-extension/dist/index.js",
   "SAP_ALLOW_PLUGIN_RAW_WRITES": "true"
   ```
   The second flag is needed because the tools make HTTP POST calls to SAP.

   Rules for `Custom_SmartFormReplace` and `Custom_AdobeFormReplace`, in the same `env` (the variable names follow the
   chosen prefix, e.g. `ZXYZ_CHECK_AUTHOR`):

   | Variable | Use | Default |
   |---|---|---|
   | `SAP_ALLOW_TRANSPORT_WRITES` | Must be `true`, otherwise the tool refuses | - |
   | `SAP_ALLOWED_PACKAGES` | Packages in which an original can be replaced | empty = none |
   | `<PREFIX>_CHECK_AUTHOR` | Check done in ABAP with the user actually logged on (`sy-uname`); `false` on systems with a shared SAP user, where the author does not tell who wrote the form | `true` |
   | `<PREFIX>_ALLOWED_TRANSPORTS` | Allowed transport requests, comma separated | all modifiable workbench requests |
4. Ask the user to **restart Claude Code** (or reconnect the ARC-1 server): the tools appear
   only afterwards. Then `ToolSearch` with `Custom_` to check them.

## Step 5 — Quick test

- `Custom_LaunchReport` with `tcode: "MB52"` (or a Z report of the project) and a narrow filter.
- `Custom_SmartFormRead` on `LE_SHP_DELNOTE` or a project form → XML saved.
- `Custom_AdobeFormRead` on `FP_TEST_00` or a project Adobe form → form XML, XDP and interface saved.
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

To use the tools: skills `sap-report-launcher`, `sap-smartform-xml` and `sap-adobe-form`.
