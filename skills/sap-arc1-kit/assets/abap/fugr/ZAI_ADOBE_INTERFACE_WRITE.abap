FUNCTION zai_adobe_interface_write
  IMPORTING
    VALUE(iv_name) TYPE fpname
    VALUE(iv_interface) TYPE xstring
  EXPORTING
    VALUE(ev_created) TYPE flag
    VALUE(ev_error) TYPE string.

  TRY.
      ev_created = NEW zai_cl_adobe_form( )->write_interface( iv_name = iv_name
                                                              iv_xml  = iv_interface ).
    CATCH zai_cx_adobe_form INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
