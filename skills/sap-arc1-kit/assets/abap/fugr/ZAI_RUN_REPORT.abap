FUNCTION zai_run_report
  IMPORTING
    VALUE(iv_report) TYPE progname OPTIONAL
    VALUE(iv_tcode) TYPE tcode OPTIONAL
    VALUE(iv_variant) TYPE raldb_vari OPTIONAL
    VALUE(it_params) TYPE rsparams_tt OPTIONAL
  EXPORTING
    VALUE(ev_report) TYPE progname
    VALUE(ev_variant) TYPE raldb_vari
    VALUE(ev_output_type) TYPE char4
    VALUE(ev_row_count) TYPE int4
    VALUE(ev_data_json) TYPE string
    VALUE(et_list) TYPE string_table
    VALUE(ev_error) TYPE string.

  TRY.
      DATA(ls_result) = NEW zai_cl_report_launcher( )->run( iv_report  = iv_report
                                                                  iv_tcode   = iv_tcode
                                                                  iv_variant = iv_variant
                                                                  it_params  = it_params ).
      ev_report      = ls_result-report.
      ev_variant     = ls_result-variant.
      ev_output_type = ls_result-output_type.
      ev_row_count   = ls_result-row_count.
      ev_data_json   = ls_result-data_json.
      et_list        = ls_result-list.
    CATCH zai_cx_launcher INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
