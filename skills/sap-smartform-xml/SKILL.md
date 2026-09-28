---
name: sap-smartform-xml
description: Reads, copies and edits SAP SmartForms without SAP GUI through XML (ARC-1 tools Custom_SmartFormRead/Custom_SmartFormWrite) and checks the result by creating the PDF preview of a real document (Custom_PrintPreview), even with a form not yet configured in NACE/TNAPR. Use it when the user wants to change texts, addresses, logos, windows or logic of a print form (delivery note, invoice, order, confirmation), make a Z copy of a standard form, replace a customer form with the changed and approved version (Custom_SmartFormReplace, under a transport request), see how a SmartForms is built, find where a printed field comes from, or see the PDF preview of an SD/MM document with a NAST message, even without saying "SmartForms" or "XML". Not for Adobe Forms (SFP) or S/4 Output Management (BRF+/APOC).
---

# SmartForms via XML, checked on the PDF

Four tools (installed by the skill `sap-arc1-kit`; the kit object prefix is the one chosen at
installation, `ZAI` by default):

| Tool | What it does |
|---|---|
| `Custom_SmartFormRead(name)` | Saves the XML of any SmartForms to `output/smartforms/<NAME>.xml` |
| `Custom_SmartFormWrite(name, file)` | Uploads the XML as a `<PREFIX>_*` form in `$TMP`: check, activation, FM generation. If the form exists, it first saves a backup in `output/smartforms/backup/` |
| `Custom_PrintPreview(document, outputType, application?, form?, program?, routine?)` | Runs the print program of the NAST message to spool (without printing) and saves the PDF in `output/print-preview/` |
| `Custom_SmartFormReplace(action, original, copy, transport, token?)` | Replaces the customer form `Z*`/`Y*` with the approved `<PREFIX>_*` copy, under the given request. `prepare`: XML backup of the original + summary + token, no writes. `execute`: with the token; refused if the original or the copy changed after `prepare` |

Intended constraints of the kit: changes are made only on copies with the kit prefix, in
`$TMP`, created by the current user; nothing is ever deleted. Standard forms are never touched;
project forms only with `Custom_SmartFormReplace`, after explicit confirmation by the user.

## Workflow

1. **Find the form and print program** of the document. From `TNAPR` (output type, medium 1):
   `SAPQuery: SELECT kappl, kschl, pgnam, ronam, sform FROM tnapr WHERE kschl = '<TYPE>' AND nacha = '1'`.
   If the output type has no TNAPR entry, ask the user for program and routine (for standard
   delivery notes: `RLE_DELNOTE` / `ENTRY`).
2. **Reference preview** of the current form: `Custom_PrintPreview` on the document.
   Show the PDF to the user and use it to understand what to change.
3. **Copy**: `Custom_SmartFormRead` of the source form, then `Custom_SmartFormWrite` with a
   `<PREFIX>_...` name on the same file. Read the copy back: apart from name, internal node IDs
   and administrative data, the XML must be the same.
4. **Check the copy**: `Custom_PrintPreview` with `form=<copy>`, `program`, `routine`.
   The PDF must be identical to the one from step 2 (`scripts/pdf_text_diff.py`).
5. **Change**: copy the XML to a new file and change only what is needed (see below),
   then `Custom_SmartFormWrite`, preview and compare with the reference: only what was meant
   to change should change.
6. **Hand-over**: tell the user where to see the result (PDF sent, spool in `SP01` with title
   `Claude preview ...`, form in transaction `SMARTFORMS` in display mode) and how to roll back
   (upload the backup file again).

7. **Replacing the original** (only if the user asks for it, with the request the user gives):
   `Custom_SmartFormReplace(action="prepare", original, copy, transport)`, show the summary and
   **wait for an explicit OK for that form**, then `action="execute"` with the token. Run the
   preview again with the original. To roll back: upload the `prepare` backup into a copy with
   `Custom_SmartFormWrite`, then prepare + execute again.
   The rules (packages, author, allowed requests) are in the project `.mcp.json`
   (see skill `sap-arc1-kit`). The tool never releases the request. In the summary check the
   **owner of the request**: if it is not the user, ask for confirmation that it is the right one.
   `execute` also saves a backup of the original before replacing it. After `execute` the form
   is in the request as `R3TR SSFO <original>`: check it with `SAPTransport(action="get")`.
   A token is valid once: after `execute` a second `execute` is refused.
   The original must already be in a transportable package. ADT does not handle SmartForms
   (`SAPManage change_package` cannot find them): to move a form out of `$TMP` use SE03
   → "Change Object Directory Entries" (`RSWBO052`, `R3TR SSFO <name>`), done by the user
   or in SAP GUI with their confirmation.

## Finding your way in the XML

The file has one line per element, so you search with `grep` and edit with targeted
replacements. Useful structure:

- `<sf:WINDOW>` with `<NAME><INAME>` = window name (e.g. `ADRESS`, `INFO`, `MAIN`).
- Each node has a `<NODETYPE>`. Codes seen in `LE_SHP_DELNOTE`: `PA` page, `WI` window,
  `TI` text, `AD` address, `GR` graphic, `CO` ABAP code, `SE` section (loop/table),
  `EV` event, `RC`/`RP` roots. For a new form count the types with
  `grep -o "<NODETYPE>[A-Z]*</NODETYPE>" file.xml | sort | uniq -c`. The output conditions of a
  node are in `sf:CONDITION`.
- **Texts** (`sf:TEXT`): the printed lines are in `<TEXT><item><TDFORMAT>/<TDLINE>`
  (original language of the form) and in `<T_TEXT>` one line per language (`<SPRAS>`).
  Changing a text = changing the line in `TEXT` **and** the entry for the print language in
  `T_TEXT`. In `TDLINE` the format tags are escaped (`&lt;TI&gt;Title&lt;/&gt;`); fields are
  `&amp;FIELD&amp;`.
- Texts with `<TTYPE>I</TTYPE>` and `<TKEY>` are include texts (SO10): their content is not in
  the form.
- **Addresses** (`sf:ADDRESS`, `NODETYPE AD`): they print the master data of `<NUMB>` (address
  number). To print a fixed address, replace the node with a text: `NODETYPE TI` and
  `sf:TEXT` with lines in `TEXT`/`T_TEXT`, keeping `sf:OUTATTR` (style and paragraphs) as is.
- Window coordinates and sizes are in `sf:OUTATTR` (`WLEFT`, `WTOP`, `WWIDTH`, `WHEIGHT`
  with their units).

For structural changes (moving nodes, new nodes) start from an existing node of the same type
and duplicate it with a script, giving it a unique `INAME`. Avoid writing XML by hand from
scratch.

## What to expect and how to read errors

| Result | Meaning |
|---|---|
| "Writing allowed only for SmartForms <PREFIX>_*" | Target not allowed: use a copy |
| "cannot be changed: package ..., author ..." | The form exists but is not in `$TMP` or belongs to another user |
| "Invalid XML: ..." | Broken file, without SmartForms namespace or without `HEADER`: nothing was written |
| "Form check: N errors, e.g. ..." | Real errors of the SmartForms check (warnings do not block); the form in SAP is unchanged |
| "saved but not generated" | Saved but the FM is not generated: open it in `SMARTFORMS` and run the check, or upload the backup again |
| "Replacement allowed only for SmartForms Z* or Y*" / "is a ... copy" | Standard original, or a copy used as original |
| "Replacement refused by the project rules" | Package, author or request not allowed by `.mcp.json` |
| "changed after prepare" | Someone changed the original or the copy after `prepare`, or the token was already used: run `prepare` again and check again |
| "The copy must be a SmartForms <PREFIX>_*" | A form without the kit prefix was passed as copy |
| "Transport request ... does not exist, is already released or is not a workbench request" | Wrong request: ask the user for the right one |
| "belongs to another user: author ..., logged-on user ..." | Author check active and form of a colleague: do not force it; on systems with a shared user it is disabled in `.mcp.json` |
| "Different original language" | Copy created from an XML in another language: create the copy again from the XML of the original |
| "... is already recorded in transport request ..." | `execute` failed after recording: the original is unchanged but is in the request; fix the copy and run prepare + execute again, or remove the object from the request before release |
| Preview: "has no print program configured (TNAPR)" | Pass `form`, `program`, `routine` together |
| Preview: HTTP 500 | The print program issued a `MESSAGE` E/A (e.g. nothing to print for that document) |

The preview does not change the NAST message, but the print program really runs: some
programs update the document or consume number ranges when they print (e.g. picking lists).
If the program is not print-only, ask for confirmation before running it.

## Limits

- SmartForms only (not Adobe Forms, not SAPscript for editing; SAPscript and Adobe forms can
  still be previewed with `Custom_PrintPreview`).
- NAST messages only; no S/4 Output Management (APOC).
- The PDF comparison is text-based: positions and graphics must be checked by the user on the PDF.
