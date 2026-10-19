FUNCTION zai_adobe_form_read
  IMPORTING
    VALUE(iv_name) TYPE fpname OPTIONAL
    VALUE(iv_interface) TYPE fpname OPTIONAL
  EXPORTING
    VALUE(ev_form) TYPE xstring
    VALUE(ev_layout) TYPE xstring
    VALUE(ev_interface) TYPE xstring
    VALUE(ev_error) TYPE string.

  " Form (XML without layout + XDP layout), its interface, or both
  IF iv_name IS INITIAL AND iv_interface IS INITIAL.
    ev_error = |Give the name of a form, of an interface or both|.
    RETURN.
  ENDIF.

  TRY.
      DATA(lo_form) = NEW zai_cl_adobe_form( ).
      IF iv_name IS NOT INITIAL.
        DATA(ls_form) = lo_form->read( iv_name ).
        ev_form   = ls_form-form.
        ev_layout = ls_form-layout.
      ENDIF.
      IF iv_interface IS NOT INITIAL.
        ev_interface = lo_form->read_interface( iv_interface ).
      ENDIF.
    CATCH zai_cx_adobe_form INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
