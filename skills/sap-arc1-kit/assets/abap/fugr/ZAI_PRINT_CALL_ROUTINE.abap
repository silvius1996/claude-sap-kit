FUNCTION zai_print_call_routine
  IMPORTING
    is_nast TYPE nast
    is_tnapr TYPE tnapr
  EXPORTING
    VALUE(ev_returncode) TYPE sysubrc
  RAISING
    zai_cx_print_preview.

  " The print program is loaded into the program group of this function group
  " and reads the work areas NAST/TNAPR (TABLES in LZAI_FG_LAUNCHERF01). The include comes after
  " the function modules, so the work areas are reached by name at runtime.
  FIELD-SYMBOLS: <ls_nast>  TYPE nast,
                 <ls_tnapr> TYPE tnapr.

  ASSIGN ('NAST') TO <ls_nast>.
  IF sy-subrc = 0.
    ASSIGN ('TNAPR') TO <ls_tnapr>.
  ENDIF.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE zai_cx_print_preview
      EXPORTING
        iv_text = |Work areas NAST/TNAPR not available in the function group|.
  ENDIF.

  <ls_nast>  = is_nast.
  <ls_tnapr> = is_tnapr.
  ev_returncode = 0.

  TRY.
      PERFORM (is_tnapr-ronam) IN PROGRAM (is_tnapr-pgnam) USING ev_returncode ' '.
    CATCH cx_sy_dyn_call_error cx_sy_program_not_found INTO DATA(lx_call).
      RAISE EXCEPTION TYPE zai_cx_print_preview
        EXPORTING
          iv_text  = |Routine { is_tnapr-ronam } not found in program { is_tnapr-pgnam }|
          previous = lx_call.
  ENDTRY.
ENDFUNCTION.
