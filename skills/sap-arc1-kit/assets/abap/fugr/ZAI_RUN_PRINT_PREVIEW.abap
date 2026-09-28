FUNCTION zai_run_print_preview
  IMPORTING
    VALUE(iv_document) TYPE nast-objky
    VALUE(iv_output_type) TYPE nast-kschl
    VALUE(iv_application) TYPE nast-kappl OPTIONAL
    VALUE(iv_language) TYPE char1 OPTIONAL
    VALUE(iv_partner) TYPE nast-parnr OPTIONAL
    VALUE(iv_device) TYPE nast-ldest OPTIONAL
    VALUE(iv_form) TYPE tdsfname OPTIONAL
    VALUE(iv_program) TYPE progname OPTIONAL
    VALUE(iv_routine) TYPE tnapr-ronam OPTIONAL
  EXPORTING
    VALUE(ev_pdf) TYPE xstring
    VALUE(ev_spool_ids) TYPE string
    VALUE(ev_program) TYPE progname
    VALUE(ev_routine) TYPE tnapr-ronam
    VALUE(ev_form) TYPE tnapr-sform
    VALUE(ev_spool_type) TYPE tsp01-rqdoctype
    VALUE(ev_error) TYPE string.

  DATA(lv_device) = COND nast-ldest( WHEN iv_device IS INITIAL THEN 'LP01' ELSE iv_device ).

  TRY.
      DATA(ls_result) = NEW zai_cl_print_preview( )->run( iv_document    = iv_document
                                                                 iv_output_type = iv_output_type
                                                                 iv_application = iv_application
                                                                 iv_language    = iv_language
                                                                 iv_partner     = iv_partner
                                                                 iv_device      = lv_device
                                                                 iv_form        = iv_form
                                                                 iv_program     = iv_program
                                                                 iv_routine     = iv_routine ).
      ev_pdf        = ls_result-pdf.
      ev_spool_ids  = concat_lines_of( table = VALUE string_table( FOR lv_id IN ls_result-spool_ids ( |{ lv_id }| ) )
                                       sep   = `,` ).
      ev_program    = ls_result-program.
      ev_routine    = ls_result-routine.
      ev_form       = ls_result-form.
      ev_spool_type = ls_result-spool_type.
    CATCH zai_cx_print_preview INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
