FUNCTION zai_adobe_form_write
  IMPORTING
    VALUE(iv_name) TYPE fpname
    VALUE(iv_form) TYPE xstring
    VALUE(iv_layout) TYPE xstring
  EXPORTING
    VALUE(ev_fm_name) TYPE rs38l_fnam
    VALUE(ev_created) TYPE flag
    VALUE(ev_ads_version) TYPE string
    VALUE(ev_error) TYPE string.

  TRY.
      DATA(ls_result) = NEW zai_cl_adobe_form( )->write( iv_name   = iv_name
                                                            iv_form   = iv_form
                                                            iv_layout = iv_layout ).
      ev_fm_name     = ls_result-fm_name.
      ev_created     = ls_result-created.
      ev_ads_version = ls_result-ads_version.
    CATCH zai_cx_adobe_form INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
