---
name: sap-adobe-form
description: Reads, copies and edits SAP Adobe forms (Interactive Forms by Adobe, transaction SFP) without SAP GUI or LiveCycle Designer, as files - the form XML (context), the layout XDP and the interface - through the ARC-1 tools Custom_AdobeFormRead/Custom_AdobeFormWrite/Custom_AdobeInterfaceWrite, checks the result on the PDF preview of a real document (Custom_PrintPreview), even with a form not yet configured in NACE/TNAPR, and gives the customer form the layout of the approved copy under a transport request (Custom_AdobeFormReplace). Use it when the user wants to change texts, fields, logos, positions, fonts or conditions of an Adobe print form (order confirmation, invoice, delivery note, purchase order), make a Z copy of a standard Adobe form, print a new field that the form does not have yet, see how a PDF form is built or find where a printed field comes from, even without saying "Adobe", "SFP" or "XDP". Not for SmartForms (skill sap-smartform-xml) or S/4 Output Management (BRF+/APOC).
---

# Adobe forms via XML and XDP, checked on the PDF

Five tools (installed by the skill `sap-arc1-kit`; the kit object prefix is the one chosen at
installation, `ZAI` by default):

| Tool | What it does |
|---|---|
| `Custom_AdobeFormRead(name, interface?)` | Saves `output/adobe-forms/<NAME>.form.xml` (form without layout: properties and context), `<NAME>.xdp` (layout) and `<INTERFACE>.interface.xml` (form interface) |
| `Custom_AdobeFormWrite(name, form, layout)` | Uploads form XML + XDP as a `<PREFIX>_*` form in `$TMP`: save, activation, function module. If the copy exists, it first saves a backup in `output/adobe-forms/backup/` |
| `Custom_AdobeInterfaceWrite(name, interface)` | Uploads an interface XML as a `<PREFIX>_*` form interface in `$TMP` and activates it. An existing one is **updated in place** (the forms using it stay linked), after a backup in `output/adobe-forms/backup/` |
| `Custom_PrintPreview(document, outputType, application?, form?, program?, routine?)` | Runs the print program of the NAST message to spool (without printing), saves the PDF, then rolls back what the print program wrote and deletes the spool; with `form` it uses a SmartForms or Adobe form not configured yet |
| `Custom_AdobeFormReplace(action, original, copy, transport, token?)` | Gives the customer form `Z*`/`Y*` the **layout** of the approved `<PREFIX>_*` copy, in place, under the given request. `prepare`: checks (only the layout may differ), XML/XDP backup of the original, summary, token; no writes. `execute`: with the token; refused if the original or the copy changed after `prepare` |

They are ARC-1 tools, named here by their short name: in Claude Code they are
`mcp__<server>__<tool>`, where `<server>` is the ARC-1 server of the target system in
`.mcp.json` (e.g. `mcp__arc1__Custom_AdobeFormRead`; the same for `SAPQuery`).

Intended constraints of the kit: changes are made only on copies with the kit prefix, in `$TMP`,
created by the current user; customer and standard forms are never written. The SAP API cannot
replace the context of an Adobe form, so `Custom_AdobeFormWrite` **deletes and creates again** an
existing copy, after saving its backup (the generated function module gets a new name each time).
Form interfaces, instead, are updated in place by `Custom_AdobeInterfaceWrite`: the forms that use
the interface print the change at the next preview, without being written again.
A customer form is changed only by `Custom_AdobeFormReplace`, after explicit confirmation by the
user: it writes the layout of the copy into the original, in place, and nothing else.

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
- [ ] 7 Original replaced (only if the user asked, after explicit OK)
```

1. **Find form and print program** of the document, from `TNAPR` (output type, medium 1):
   `SAPQuery: SELECT kappl, kschl, pgnam, ronam, sform, formtype FROM tnapr WHERE kschl = '<TYPE>' AND nacha = '1'`.
   The form is an Adobe form if `SELECT name FROM fplayout WHERE name = '<FORM>' AND state = 'A'`
   finds it. If the output type has no TNAPR entry, ask the user for program and routine. Program and
   routine must be configured in TNAPR for some output type, listed in the TVARVC variable
   `ZAI_PREVIEW_PROGRAMS` or be a local program of the user; otherwise the preview is refused.
2. **Reference preview** of the current form: `Custom_PrintPreview` on the document. Show the PDF
   to the user and use it to understand what to change.
3. **Copy**: `Custom_AdobeFormRead` of the source form, then `Custom_AdobeFormWrite` with a
   `<PREFIX>_...` name and the two files `.form.xml` and `.xdp`. Read the copy back: the form XML
   must be the same apart from the form name, the layouts per language (`<LAYOUTT>`) and the
   administrative data (users, dates; the tool
   renumbers the object ids `id="o42"` / `href="#o42"` and empties `CACHE_INFO`, so the same form
   always gives the same XML), the XDP apart from the XML declaration and the `timeStamp` of the
   `xdp` element, renewed at every write.
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
6. **Hand-over**: tell the user where to see the result (PDF; the spool request is deleted after the
   preview unless `keepSpool` was passed; form in transaction `SFP` in display mode), how to roll back (upload the
   backup files again with `Custom_AdobeFormWrite`) and that the original form is unchanged: the
   user decides how to bring the change into it. A change of the layout only goes in with step 7;
   changes of context or interface are made by the user in `SFP`.
7. **Replacing the original** (only if the user asks for it, with the request the user gives):
   `Custom_AdobeFormReplace(action="prepare", original, copy, transport)`, show the summary and
   **wait for an explicit OK for that form**, then `action="execute"` with the token.
   - Only the **layout** is written. `prepare` compares the form XML of copy and original and refuses
     the copy if anything else differs (context, interface, properties), listing the lines. If the
     list shows only administrative data (users, dates), it is a defect of the kit: report it to the
     user instead of working around it.
   - The original must already be in a transportable package, without an inactive version (someone
     changing it in `SFP`). `transport` is the request, not one of its tasks. The rules (packages,
     author, allowed requests) are in the project `.mcp.json` (see skill `sap-arc1-kit`); in the
     summary check the **owner of the request**: if it is not the user, ask whether it is the right one.
   - After `execute`: preview again with the original (without `form`) and compare it with the
     preview of the copy; check the request with `SAPTransport(action="get")`: it contains
     `R3TR SFPF <original>`. The tool never releases the request, and a token is valid once.
   - The layout is written in the original language of the form and SAP generates the layouts of the
     other languages again from it, as when the form is saved in `SFP` (see "Languages"): preview in
     the languages the documents use, and tell the user to check the translations (`SE63`).
   - The layouts per language (`<LAYOUTT>` in the form XML) are not compared: they come from the layout.
   - To roll back: upload the backup of `prepare` (or of `execute`) into a copy with
     `Custom_AdobeFormWrite`, then prepare + execute again.

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
- **Interface** (`.interface.xml`): parameters, global data, types and initialization code. Customer
  and standard interfaces are never written: to change one, make a `<PREFIX>_*` interface from its file
  with `Custom_AdobeInterfaceWrite` and point the copy of the form to it (see below).

## Printing a field the form does not have yet

The data reach the layout in three steps: **interface** (global data filled by the initialization
code) → **context** of the form (a node per field) → **binding** of an XDP field. Example with a form
whose context has the node of the print structure `SLS_PRT_COM` (the sales document forms):

1. **Interface.** From `<SOURCE_IF>.interface.xml` read with `Custom_AdobeFormRead`, make a new file:
   - in `<GLOBAL_DATA>` add an `<SFPGDATA>` with `<NAME>GV_NEW_TEXT</NAME>`, `<TYPING>TYPE</TYPING>`,
     `<TYPENAME>STRING</TYPENAME>` (empty `<DEFAULTVAL/>`, `<CONSTANT/>`);
   - in `<INITIALIZATION>` add `<FPCLINE>` lines that fill it, between comments that mark the change
     (`* <PREFIX> begin` / `* <PREFIX> end`). Use explicit field lists and no SELECT in loops, and
     escape `'` `<` `>` `&` as XML (`&apos;`, `&lt;`, `&gt;`, `&amp;`): change the file with a small
     script and check the diff.

   Then `Custom_AdobeInterfaceWrite` with a `<PREFIX>_*` name: "created in $TMP and active". A syntax
   error in the code ends with "saved but not activated": fix the file and write again.
2. **Form.** In the form XML of the copy set `<INTERFACE><PREFIX>_..._IF</INTERFACE>` and add to the
   context a data node for the new field under the node `SLS_PRT_COM`: a `cls:CL_FP_DATA` with
   `<NAME>` and `<FIELD>` = `GV_NEW_TEXT`, `<STATE>A</STATE>`, a new 32-character hex `<ID>`, `<PARENT>`
   pointing to the `SLS_PRT_COM` node, its own empty `cls:CL_FP_CONDITION`, linked into the chain of
   `<SUCCESSOR>` of its siblings (copy an existing node such as another `GV_*` field and adapt it).
3. **Layout.** In the XDP add (or copy) a `<field>` with
   `<bind match="dataRef" ref="$record.SLS_PRT_COM.GV_NEW_TEXT"/>`, with caption and position.
4. `Custom_AdobeFormWrite` of the copy, preview, compare: only the new line should differ.

Later changes to the code or the data are made only on the interface (`Custom_AdobeInterfaceWrite`
with the same name: "updated in place"); the form copy does not need to be written again. To roll
back, upload the backup file saved by the tool.
- **Languages.** The `.xdp` file is the layout of the original language of the form. The layouts of
  the translations are in the form XML (`<LAYOUTT>`, one `<FPLAYOUTT>` per `<LANGUAGE>`, XDP in base64).
  Whether SAP generates them again from a changed `.xdp` depends on the case (seen on S/4HANA 816: a
  copy written once kept the old ones, another one and the original after `Custom_AdobeFormReplace`
  got the new layout in every language): always preview in the languages the documents use, and tell
  the user that the translations (`SE63`) must follow. The `<tags>` element at the top of the XDP holds
  the texts for the translation (`<value id="...">`, the `xliff:id` of the text): SAP writes it again
  from the texts of the template at every write, so a change made only in `<tags>` is lost. Change
  the text in the template (`<draw>`, caption, `<desc>`).

## What to expect and how to read errors

| Result | Meaning |
|---|---|
| "Writing allowed only for Adobe forms <PREFIX>_*" / "... form interfaces <PREFIX>_*" | Target not allowed: use a copy |
| "The file is not the XML of a form interface" | A form XML or another file was passed as interface: pass the `.interface.xml` |
| "XML schema based interfaces are not supported" / "the interface type cannot be changed" | Only ABAP dictionary based interfaces are written, and an existing one keeps its type |
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
| Preview of a changed copy prints the old text | The document is printed in a translation, not in the original language (see "Languages"). ADS caches layouts under `timeStamp` and `uuid` of the XDP: the tool renews the `timeStamp`, so a layout changed outside the kit with the old one can also print as before |
| Preview: HTTP 500 | The print program issued a `MESSAGE` E/A (e.g. nothing to print for that document) |
| "Replacement allowed only for Adobe forms Z* or Y*" / "is a <PREFIX>_* copy" | Standard original, or a copy used as original |
| "The copy must be an Adobe form <PREFIX>_*" | A form without the kit prefix was passed as copy |
| "differs from ... outside the layout" | The copy changed context, interface or properties: only a layout change is replaced; the rest goes into the original in `SFP` |
| "is a task of request ..." / "does not exist" / "already released or is not a workbench request" | Wrong request: ask the user for the right one |
| "is not in the object directory or is local ($TMP)" | The original is not transportable: it cannot be replaced |
| "belongs to another user: author ..., logged-on user ..." | Author check active and form of a colleague: do not force it; on systems with a shared user it is disabled in `.mcp.json` |
| "has an inactive version" | Someone is changing the original in `SFP`: it must be activated or discarded first |
| "Replacement refused by the project rules" | Package or request not allowed by `.mcp.json` |
| "changed after prepare" | The original or the copy changed after `prepare`, or the token was already used: run `prepare` again |
| "... is already recorded in transport request ..." | `execute` failed after recording: the original may be unchanged but is in the request; fix and run prepare + execute again, or remove the object from the request before release |

The preview does not change the NAST message, but the print program really runs: if the program
is not print-only, ask for confirmation before running it.

## Limits

- The customer form gets only the layout of the copy, in the original language: context, interface,
  properties and translations are changed by the user in `SFP` / `SE63`.
- Interfaces: only `<PREFIX>_*` copies; XML schema based interfaces are not written.
- NAST messages only for the preview; forms used by S/4 Output Management (BRF+/APOC) can be read
  and copied, not previewed.
- The PDF comparison is text-based: positions, fonts and graphics must be checked by the user on the PDF.
