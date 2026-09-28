FUNCTION zai_smartform_read
  IMPORTING
    VALUE(iv_name) TYPE tdsfname
  EXPORTING
    VALUE(ev_xml) TYPE xstring
    VALUE(ev_error) TYPE string.

  TRY.
      ev_xml = NEW zai_cl_smartform_xml( )->read( iv_name ).
    CATCH zai_cx_smartform INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
