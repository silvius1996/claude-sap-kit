# Changelog

## 0.7.0

Replacement of a customer Adobe form with the approved copy, for layout changes. Tested live on S/4HANA
(SAP_BASIS 816) with ADS on a `Z` copy of `FP_TEST_00` in a transportable package; on 7.50 checked with
abaplint only (the `LOAD` parameters used for the replacement are not verified there yet).

- `Custom_AdobeFormReplace`: gives a customer Adobe form (`Z*`/`Y*`, in a transportable package) the layout of the
  approved `ZAI_*` copy, recording it in the given transport request. Two steps as for SmartForms: `prepare`
  (checks, XML/XDP backup of the original, summary with the owner of the request, one-time token; no writes) and
  `execute` (with the token, refused if the original or the copy changed). The layout is written in place
  (`CL_FP_WB_FORM=>LOAD` in write mode, `SET_LAYOUT_DATA`, `SAVE`, activation): the SAP API cannot replace the
  context of a form, so the copy is refused if its form XML differs from the original outside the layout
  (context, interface, properties), with the differing lines. Also refused: a task instead of its request (the
  message names the request), an original with an inactive version, project rules of `.mcp.json`.
- Fixes from the live test of `Custom_AdobeFormReplace`:
  - `execute` ended in a short dump (`DYNPRO_SEND_IN_BACKGROUND`) when the original language of the form was not
    the logon language of the SOAP call: locking the form asked in a popup whether to change the original
    language. The form is now opened in its original language without language check and without dialogs
    (`LOAD` with `I_LANGUAGE`, `I_SUPPRESS_LANGUAGE_CHECK`, `I_ORDERNUM`, `I_DARK`); this also writes the layout
    of the original language, not a new translation in the logon language.
  - `prepare` refused a copy with a changed layout because it compared the layouts per language (`<LAYOUTT>` in
    the form XML), which SAP generates from the layout. They are no longer compared.
  - The summary no longer says that translated layouts stay as they are: after `execute` SAP generates the
    layouts of the other languages again from the new one, as when the form is saved in SFP.
- Skill `sap-adobe-form`: SAP writes the `<tags>` of the XDP (texts for the translation) again from the texts of
  the template at every write, so a text is changed in the template, not in `<tags>`.
- `Custom_AdobeFormRead`: object ids renumbered in document order and `CACHE_INFO` emptied, as abapGit does, so the
  same form always gives the same XML and copy and original can be compared line by line.
- Fix: with `ZAI_CHECK_AUTHOR=false` the author check of `Custom_SmartFormReplace` stayed on, because SOAP-RFC drops
  the empty parameter and the function module default `'X'` applied. A check switched off is now sent as `'-'`.
- Fix: the object prefix may have at most 8 characters, not 10: with 9 or 10 the function module
  `<PREFIX>_ADOBE_INTERFACE_WRITE` (since 0.6.0) exceeded the 30 characters allowed by SAP. `set_prefix.py` refuses
  longer prefixes.
- README: Adobe form interfaces are no longer read only (`Custom_AdobeInterfaceWrite`, since 0.6.0).
- New remote-enabled FM `ZAI_ADOBE_FORM_REPLACE`; 8 more ABAP Unit tests (harmless) in `ZAI_CL_ADOBE_FORM`
  (22 in all); 36 Node tests.

## 0.6.0

Adobe forms (Interactive Forms by Adobe, transaction SFP). Tested live on S/4HANA (SAP_BASIS 816) with ADS:
read of `FP_TEST_00` and of the sales document form `SD_SDOC_FORM01`, copy, preview of an order with the copy
(same text as the original), text change in the XDP, preview and rollback; a new printed field read from a `Z`
form interface; update in place of that interface (initialization code), preview, creation of a second interface,
refusals and rollback from the backup. Not tested live on SAP_BASIS 7.50 (ECC) yet: the ABAP sources pass
abaplint with the v750 syntax only.

- `Custom_AdobeFormRead`: downloads any Adobe form as three files, as abapGit does: the form XML without layout
  (`<NAME>.form.xml`, one element per line), the layout as XDP (`<NAME>.xdp`) and the form interface
  (`<INTERFACE>.interface.xml`, found in the form XML or passed explicitly).
- `Custom_AdobeFormWrite`: uploads form XML + XDP as a `ZAI_*` copy in `$TMP` of the logged-on user, activates it and
  returns the generated function module. Checks Adobe Document Services (ADS) first. The SAP API updates the layout
  of a loaded form in place but cannot replace its context (abapGit deletes and creates the form again too), so an
  existing copy is deleted and created again after a local backup; customer and standard forms are never written.
  The `timeStamp` of the `xdp` element is renewed at every write, as LiveCycle Designer does: ADS caches the template
  under `timeStamp` and `uuid`, and a changed layout with the old `timeStamp` was printed unchanged.
- `Custom_AdobeInterfaceWrite`: uploads an interface XML (parameters, global data, types, initialization code,
  reference fields) as a `ZAI_*` form interface in `$TMP` and activates it. Unlike forms, an existing `ZAI_*`
  interface is updated in place with the setters of `IF_FP_INTERFACE_DATA`, so the forms using it stay linked and
  print the change at the next preview, without being regenerated; its current version is saved first in
  `output/adobe-forms/backup`, and uploading the backup is the rollback. Refuses non-`ZAI_*` names (checked
  before any call, so no backup file is written for them), interfaces of other users or outside `$TMP`, XML schema
  based interfaces, a change of interface type, and a file that is not an interface XML (such as a form XML).
  Both write tools now check the `ZAI_*` name locally first.
- `Custom_PrintPreview`: `form` also accepts an active Adobe form, always with form type `2` (PDF, domain
  `NA_FORMTYPE`): print programs such as `SD_SDOC_PRINT01` refuse a form of another type. For SmartForms the form type
  comes from the TNAPR entry of the output type when its form is a SmartForms too.
- New ABAP objects `ZAI_CL_ADOBE_FORM`, `ZAI_CX_ADOBE_FORM` and the remote-enabled FMs `ZAI_ADOBE_FORM_READ`,
  `ZAI_ADOBE_FORM_WRITE`, `ZAI_ADOBE_INTERFACE_WRITE`; 14 ABAP Unit tests (harmless) for the new class, 2 more for
  the preview. 27 Node tests for the extension.
- New skill `sap-adobe-form`: workflow copy → preview → change → compare, how to find one's way in the XDP and in the
  context, how to add a printed field through a `ZAI_*` interface, errors and limits. Replacing the original form
  under a transport request is not part of this version.

## 0.5.2

Skills reviewed against Anthropic's skill authoring best practices. No change to the tools or the ABAP sources.

- Script paths use `${CLAUDE_SKILL_DIR}`, so `set_prefix.py` and `pdf_text_diff.py` are found wherever the plugin
  is installed (before: a `<skill>` placeholder and a path relative to the skill folder).
- ARC-1 tools are explained with their full Claude Code name (`mcp__<server>__<tool>`), to pick the right server
  when several are configured.
- `pdf_text_diff.py`: `pypdf` is listed in the skill; a missing package, a missing file or an unreadable PDF now
  end with a clear message and exit code 2.
- Checklists to copy for the installation and for a SmartForms change; the PDF comparison is an explicit loop
  (compare, fix, repeat).
- One placeholder for the prefix (`<PREFIX>`); test history moved out of the installation skill.
- `evals/`: three cases for `claude plugin eval` (narrow report filters, copy before changing a form, checks before
  installing). With the plugin 1.00 on all three, without 0.00.
- Extension version aligned with the plugin (`index.ts` and `package.json` said 0.5.0).

## 0.5.1

- Fix: the ABAP Unit test classes of `ZAI_CL_PRINT_PREVIEW` and `ZAI_CL_SMARTFORM_XML` did not compile
  on SAP_BASIS 7.50, so the two classes could not be activated on ECC. They used
  `CL_ABAP_UNIT_ASSERT=>SKIP`, which is not available on 7.50. Tests that find no suitable data
  on the system now end with a tolerable assertion (`FAIL` with `LEVEL = TOLERABLE`) instead of
  being skipped: ARC-1 reports it as `failed` with `severity: tolerable` (see SKILL.md, step 3).
- Fix: `ZAI_CL_PRINT_PREVIEW` did not compile on 7.50: `CALL FUNCTION ... EXPORTING is_nast = prepare_nast( is_nast = ... )`
  is read as a duplicate formal parameter `IS_NAST`. The NAST copy is now built in a separate variable first.
- Fix: the test `missing_config` of `ZAI_CL_PRINT_PREVIEW` joined NAST with TNAPR and could read the whole
  NAST on systems with many messages, exceeding the 60 second limit of ABAP Unit. It now uses an output
  type without TNAPR entry and no NAST record.
- ATC on ECC (variant DEFAULT) had one priority 1 and one priority 2 finding: pseudo comment `CI_NOFIRST` added to
  the TSP01 read by title in `find_spools` (on ECC TSP01 has only the index RQFINAL/RQCLIENT/RQOWNER), and the
  variant list of `ZAI_CL_REPORT_LAUNCHER=>get_variants` is sorted in ABAP, because `ORDER BY` bypassed the
  buffer of VARID.
- Tested live on ECC 6.0 EHP8 (SAP_BASIS 750) and S/4HANA 2025 (SAP_BASIS 816).

## 0.5.0

- Compatible with SAP_BASIS 7.50: `RAISE EXCEPTION TYPE ... EXPORTING` instead of
  `RAISE EXCEPTION NEW`, POSIX regular expressions instead of PCRE.
