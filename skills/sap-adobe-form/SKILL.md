---
name: sap-adobe-form
description: Reads, copies and edits SAP Adobe forms (Interactive Forms by Adobe, transaction SFP) without SAP GUI or LiveCycle Designer, as files - the form XML (context), the layout XDP and the interface - through the ARC-1 tools Custom_AdobeFormRead/Custom_AdobeFormWrite, and checks the result on the PDF preview of a real document (Custom_PrintPreview), even with a form not yet configured in NACE/TNAPR. Use it when the user wants to change texts, fields, logos, positions, fonts or conditions of an Adobe print form (order confirmation, invoice, delivery note, purchase order), make a Z copy of a standard Adobe form, see how a PDF form is built or find where a printed field comes from, even without saying "Adobe", "SFP" or "XDP". Not for SmartForms (skill sap-smartform-xml) or S/4 Output Management (BRF+/APOC).
---

# Adobe forms via XML and XDP, checked on the PDF

Three tools (installed by the skill `sap-arc1-kit`; the kit object prefix is the one chosen at
installation, `ZAI` by default):

| Tool | What it does |
|---|---|
| `Custom_AdobeFormRead(name, interface?)` | Saves `output/adobe-forms/<NAME>.form.xml` (form without layout: properties and context), `<NAME>.xdp` (layout) and `<INTERFACE>.interface.xml` (form interface) |
| `Custom_AdobeFormWrite(name, form, layout)` | Uploads form XML + XDP as a `<PREFIX>_*` form in `$TMP`: save, activation, function module. If the copy exists, it first saves a backup in `output/adobe-forms/backup/` |
| `Custom_PrintPreview(document, outputType, application?, form?, program?, routine?)` | Runs the print program of the NAST message to spool (without printing) and saves the PDF; with `form` it uses a SmartForms or Adobe form not configured yet |

They are ARC-1 tools, named here by their short name: in Claude Code they are
`mcp__<server>__<tool>`, where `<server>` is the ARC-1 server of the target system in
`.mcp.json` (e.g. `mcp__arc1__Custom_AdobeFormRead`; the same for `SAPQuery`).

Intended constraints of the kit: changes are made only on copies with the kit prefix, in `$TMP`,
created by the current user; customer and standard forms are never written. SAP has no API to
update an Adobe form, so `Custom_AdobeFormWrite` **deletes and creates again** an existing copy,
after saving its backup. Replacing the customer form with the copy is not part of the kit yet.

**Adobe Document Services (ADS)** must work on the system: without ADS a form is not saved and
nothing is printed. `Custom_AdobeFormWrite` checks it and says so; the standard report
`FP_TEST_00` is the manual check for the user or the Basis team.

## Workflow

Copy this checklist into your answer and tick it off as you go:

```
Adobe form change:
- [ ] 1 Form, interface and print program found
- [ ] 2 Reference preview of the current form
- [ ] 3 <PREFIX>_* copy created and read back
- [ ] 4 Copy preview identical to the reference
- [ ] 5 Change made, preview differs only where intended
- [ ] 6 Hand-over: where to see it, how to roll back, how to bring it into the original
```

1. **Find form and print program** of the document, from `TNAPR` (output type, medium 1):
   `SAPQuery: SELECT kappl, kschl, pgnam, ronam, sform, formtype FROM tnapr WHERE kschl = '<TYPE>' AND nacha = '1'`.
   The form is an Adobe form if `SELECT name FROM fplayout WHERE name = '<FORM>' AND state = 'A'`
   finds it. If the output type has no TNAPR entry, ask the user for program and routine.
2. **Reference preview** of the current form: `Custom_PrintPreview` on the document. Show the PDF
   to the user and use it to understand what to change.
3. **Copy**: `Custom_AdobeFormRead` of the source form, then `Custom_AdobeFormWrite` with a
   `<PREFIX>_...` name and the two files `.form.xml` and `.xdp`. Read the copy back: apart from
   name and administrative data, form XML and XDP must be the same.
4. **Check the copy**: `Custom_PrintPreview` with `form=<copy>`, `program`, `routine`. The PDF
   must be identical to the one from step 2. Compare the text with the script of the skill
   `sap-smartform-xml` (needs `pip install pypdf`):
   ```bash
   python "${CLAUDE_SKILL_DIR}/../sap-smartform-xml/scripts/pdf_text_diff.py" <reference.pdf> <copy.pdf>
   ```
   It prints "Identical text" (exit code 0) or the different lines (exit code 1). If the copy
   differs, find the cause before going on.
5. **Change**: copy the files to new ones and change only what is needed (see below), then
   `Custom_AdobeFormWrite`, preview and compare with the reference: only what was meant to
   change should change. If something else changed, fix the files and repeat.
6. **Hand-over**: tell the user where to see the result (PDF, spool in `SP01` with title
   `Claude preview ...`, form in transaction `SFP` in display mode), how to roll back (upload the
   backup files again with `Custom_AdobeFormWrite`) and that the original form is unchanged: the
   user decides how to bring the change into it (in `SFP`, or by configuring the copy in NACE
   under a transport request).

## Finding your way in the layout (XDP)

The XDP is the XML of Adobe LiveCycle Designer (XFA). Search with `grep -n` and edit with
targeted replacements or small scripts; never rewrite the file by hand.

- `<xdp:xdp>` → `<template>`: the whole layout.
- **Master pages**: `<pageSet>` → `<pageArea>`, with the `<contentArea>` (x, y, w, h) where the
  body flows and the fixed elements printed on every page (logo, header, footer).
- **Body**: nested `<subform>` elements. `layout="tb"` means flowed from top to bottom;
  without it the children are positioned with `x`, `y`, `w`, `h` and units (`mm`, `in`, `pt`).
  `<occur>` repeats a subform (table rows), `<break>` and `<overflow>` move content to the next page.
- **Static texts**: `<draw>` with `<value><text>` or `<value><exData contentType="text/html">`
  (rich text in XHTML: keep the markup, change only the text).
- **Data fields**: `<field>` with `<bind match="dataRef" ref="..."/>`: the reference (for example
  `$.NODE.FIELD` or `$record.NODE.FIELD`) is a node of the form context. A field printed inside a
  rich text is an embedded `<span>` in the `exData`.
- **Format**: `<font typeface size weight>`, `<para hAlign>`, `<border>`, `<margin>`; field
  patterns for dates and amounts in `<format>`/`<picture>`.
- **Scripts**: `<event activity="...">` with `<script>` (FormCalc by default, JavaScript with
  `contentType="application/x-javascript"`). They hide fields, compute values or change the
  layout: read the scripts of a field before changing it.
- **Images**: embedded in `<image>` (base64), or from the context through a field with `<imageEdit/>`.

Useful searches: `grep -n "<printed text>" <NAME>.xdp` to find a static text,
`grep -n 'ref="' <NAME>.xdp` for the data bindings, `grep -n '<script' <NAME>.xdp` for the logic.

## The form XML and the interface

- **Form XML** (`.form.xml`): properties of the form (interface, languages) and the **context**:
  which interface data reach the layout, with texts (SO10 or form texts), addresses, graphics
  and conditions. Look at it with `grep -n` on the node names shown by the layout bindings.
  Change the context only when the layout needs data it does not have yet; the bindings in the
  XDP must follow.
- **Interface** (`.interface.xml`): parameters, global data and initialization code. Read only:
  changes to the interface are made by the user in `SFP`.
- Static texts of the layout are translated with XLIFF (`SE63`): after changing a text, tell the
  user that the other languages may need a new translation.

## What to expect and how to read errors

| Result | Meaning |
|---|---|
| "Writing allowed only for Adobe forms <PREFIX>_*" | Target not allowed: use a copy |
| "cannot be changed: package ..., author ..." | The form exists but is not in `$TMP` or belongs to another user |
| "exists without object directory entry" | Not a copy made by the kit: choose another name |
| "Layout (XDP) missing" / "Invalid layout" | Pass the `.xdp` file; its root must be `xdp:xdp` |
| "Invalid form XML: ..." | Broken file or not the XML of an Adobe form: nothing was written |
| "Layout not accepted" | SAP refused the XDP: compare it with the last one that worked |
| "Adobe Document Services (ADS) not configured" / "not reachable" | ADS missing or down: ask the user or the Basis team (`FP_TEST_00`) |
| "not saved ... the previous version of the copy was already deleted" | Upload the backup files again with `Custom_AdobeFormWrite` |
| "saved but not activated" | The form has errors (for example a context that does not match the interface): open it in `SFP` in display mode, fix the files and write again |
| "active but function module not available" | Generation failed: open the form in `SFP` and activate it there |
| Preview: "neither SmartForms nor Adobe form" / "has no function module" | Wrong name or form not active |
| Preview: HTTP 500 | The print program issued a `MESSAGE` E/A (e.g. nothing to print for that document) |

The preview does not change the NAST message, but the print program really runs: if the program
is not print-only, ask for confirmation before running it.

## Limits

- Copies only: replacing the customer form with the copy is not available yet.
- Interface read only.
- NAST messages only for the preview; forms used by S/4 Output Management (BRF+/APOC) can be read
  and copied, not previewed.
- The PDF comparison is text-based: positions, fonts and graphics must be checked by the user on the PDF.
