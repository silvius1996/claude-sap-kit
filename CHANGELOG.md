# Changelog

## 0.6.0 (not released yet: to be tested live)

Adobe forms (Interactive Forms by Adobe, transaction SFP).

- `Custom_AdobeFormRead`: downloads any Adobe form as three files, as abapGit does: the form XML without layout
  (`<NAME>.form.xml`, one element per line), the layout as XDP (`<NAME>.xdp`) and the form interface
  (`<INTERFACE>.interface.xml`, found in the form XML or passed explicitly).
- `Custom_AdobeFormWrite`: uploads form XML + XDP as a `ZAI_*` copy in `$TMP` of the logged-on user, activates it and
  returns the generated function module. Checks Adobe Document Services (ADS) first. SAP has no API to update a form
  (abapGit deletes and creates it again too), so an existing copy is deleted and created again after a local backup;
  customer and standard forms are never written.
- `Custom_PrintPreview`: `form` also accepts an active Adobe form; the form type comes from the TNAPR entry of the
  output type when its form is of the same kind.
- New ABAP objects `ZAI_CL_ADOBE_FORM`, `ZAI_CX_ADOBE_FORM` and the remote-enabled FMs `ZAI_ADOBE_FORM_READ`,
  `ZAI_ADOBE_FORM_WRITE`; 9 ABAP Unit tests (harmless) for the new class, 2 more for the preview.
- New skill `sap-adobe-form`: workflow copy → preview → change → compare, how to find one's way in the XDP and in the
  context, errors and limits. Replacing the original form under a transport request is not part of this version.

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
