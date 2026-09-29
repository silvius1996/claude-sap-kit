# Changelog

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
