# Changelog

## 0.5.1

- Fix: the ABAP Unit test classes of `ZAI_CL_PRINT_PREVIEW` and `ZAI_CL_SMARTFORM_XML` did not compile
  on SAP_BASIS 7.50, so the two classes could not be activated on ECC. They used
  `CL_ABAP_UNIT_ASSERT=>SKIP`, which is not available on 7.50. Tests that find no suitable data
  on the system now end with a tolerable warning (`FAIL` with `LEVEL = TOLERABLE`) instead of
  being skipped. The productive code is unchanged.
- Tested live on ECC 6.0 EHP8 (SAP_BASIS 750) and S/4HANA 2025 (SAP_BASIS 816).

## 0.5.0

- Compatible with SAP_BASIS 7.50: `RAISE EXCEPTION TYPE ... EXPORTING` instead of
  `RAISE EXCEPTION NEW`, POSIX regular expressions instead of PCRE.
