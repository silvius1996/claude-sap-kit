FUNCTION zai_smartform_write
  IMPORTING
    VALUE(iv_name) TYPE tdsfname
    VALUE(iv_xml) TYPE xstring
  EXPORTING
    VALUE(ev_fm_name) TYPE rs38l_fnam
    VALUE(ev_created) TYPE flag
    VALUE(ev_error) TYPE string.

  TRY.
      DATA(ls_result) = NEW zai_cl_smartform_xml( )->write( iv_name = iv_name
                                                               iv_xml  = iv_xml ).
      ev_fm_name = ls_result-fm_name.
      ev_created = ls_result-created.
    CATCH zai_cx_smartform INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
