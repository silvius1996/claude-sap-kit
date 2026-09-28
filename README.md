# claude-sap-kit

Tools and skills that let **Claude Code** work on an **on-premise SAP system** without SAP GUI,
built as an extension of [ARC-1](https://github.com/arc-mcp/arc-1).

ARC-1 already gives Claude read and write access to ABAP code through ADT. This kit adds what
ADT does not cover: running reports, previewing print output and editing SmartForms.

## What you can ask Claude

- *"Run MB52 for plant 1001, storage locations M001 to M003"* → runs the report and reads the ALV as JSON.
- *"Compare ZMM_STOCK with its copy on the same filters"* → same selection on both, row-by-row comparison.
- *"Show me the PDF of delivery 80012345"* → preview of the NAST message, nothing is printed.
- *"On the delivery note, replace the sender address with a fixed text"* → Z copy of the SmartForms,
  XML edit, PDF preview and comparison with the original.
- *"OK, move the change to the original form in request DEVK900123"* → controlled replacement, with backup,
  summary and explicit confirmation.

## How it works

```
Claude Code ──MCP──▶ ARC-1 ──▶ extension (5 Custom_* tools) ──HTTP /sap/bc/soap/rfc──▶ remote-enabled FMs ZAI_* ──▶ ABAP classes
```

| Tool | What it does |
|---|---|
| `Custom_LaunchReport` | `SUBMIT` of a report (by name or transaction) with a variant and/or selection values; returns the ALV as JSON or the list as text |
| `Custom_PrintPreview` | Runs the print program of a NAST message to spool and saves the PDF, even with a form not yet configured in NACE |
| `Custom_SmartFormRead` | Downloads the XML of any SmartForms |
| `Custom_SmartFormWrite` | Uploads an XML as a `ZAI_*` copy in `$TMP`, with check, activation and FM generation |
| `Custom_SmartFormReplace` | Replaces a customer form with the approved copy, under a transport request, in two steps (`prepare` → `execute`) |

ARC-1 extensions can only make HTTP calls, so the tools call remote-enabled function modules
through the standard SOAP-RFC service.

## Repository layout

```
.claude-plugin/                  Claude Code plugin and marketplace
skills/
  sap-arc1-kit/                  skill: installs the kit on an SAP system
    assets/abap/                 ABAP classes and function group (default prefix ZAI)
    assets/arc1-extension/       ARC-1 extension in TypeScript, with tests
    scripts/set_prefix.py        changes the object prefix (e.g. ZAI → ZXYZ)
  sap-report-launcher/           skill: how to run and compare reports
  sap-smartform-xml/             skill: how to read, edit and check SmartForms
```

## Requirements

- SAP NetWeaver / S/4HANA with ABAP 7.50 or later. Tested on S/4HANA 2025 (SAP_BASIS 816).
- [ARC-1](https://github.com/arc-mcp/arc-1) 1.4.0 or later, configured in Claude Code with writes enabled.
- SICF service `/sap/bc/soap/rfc` active.
- SAP user with `S_RFC` on the kit function group, plus the authorizations for the reports to run and for spool requests.
- Node.js 22.19+ or 24 (to build the extension) and Python 3 (for the scripts).

## Installation

1. **Plugin** (the three skills), from Claude Code:
   ```
   /plugin marketplace add silvius1996/claude-sap-kit
   /plugin install sap-arc1-kit@claude-sap-kit
   ```
2. **Kit on the SAP system**: with ARC-1 connected, ask Claude *"install the ARC-1 kit on this system"*.
   The skill `sap-arc1-kit` goes through every step: prefix, creation and activation of the ABAP objects,
   ABAP Unit tests, build of the extension and `.mcp.json` configuration.
   The steps are also described in [skills/sap-arc1-kit/SKILL.md](skills/sap-arc1-kit/SKILL.md)
   if you prefer to do them by hand.
3. Restart Claude Code: the `Custom_*` tools appear after the restart.

Minimal extension configuration in the ARC-1 server of `.mcp.json`:

```json
"env": {
  "ARC1_PLUGINS": "<absolute path>/arc1-extension/dist/index.js",
  "SAP_ALLOW_PLUGIN_RAW_WRITES": "true"
}
```

## Safety

The kit is designed to be safe even when an AI is driving it:

- standard SAP objects are never changed;
- SmartForms are written only as copies with the kit prefix, in `$TMP`, created by the logged-on user;
  every overwrite first saves an XML backup;
- replacing a customer form needs a transport request given by the user, a `prepare` step with a summary
  and a one-time token, and is refused if the original or the copy changed in the meantime;
- allowed packages, allowed requests and the author check are configured in the project `.mcp.json`;
- nothing is ever deleted;
- the skills ask for confirmation before running reports or print programs that change data.

## Limits

- Print output with NAST messages only: no S/4 Output Management (BRF+/APOC).
- Editing is for SmartForms only. Adobe Forms and SAPscript can be previewed but not edited.
- Reports that open popups, `CALL SCREEN` or dialog transactions cannot be run.

## Tests

```bash
cd skills/sap-arc1-kit/assets/arc1-extension
npm ci --ignore-scripts
npm test
```

The ABAP classes come with ABAP Unit tests: the installation skill runs them on the system.

## License

[MIT](LICENSE). ARC-1 is a separate project, also under the MIT license.
