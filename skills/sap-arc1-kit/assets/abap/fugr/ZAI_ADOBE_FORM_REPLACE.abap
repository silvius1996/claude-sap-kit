FUNCTION zai_adobe_form_replace
  IMPORTING
    VALUE(iv_mode) TYPE char1
    VALUE(iv_original) TYPE fpname
    VALUE(iv_copy) TYPE fpname
    VALUE(iv_transport) TYPE trkorr
    VALUE(iv_token) TYPE string OPTIONAL
    VALUE(iv_check_author) TYPE char1 DEFAULT 'X'
  EXPORTING
    VALUE(ev_form) TYPE xstring
    VALUE(ev_layout) TYPE xstring
    VALUE(ev_token) TYPE string
    VALUE(ev_devclass) TYPE devclass
    VALUE(ev_author) TYPE responsibl
    VALUE(ev_lastuser) TYPE syuname
    VALUE(ev_tr_owner) TYPE as4user
    VALUE(ev_fm_name) TYPE rs38l_fnam
    VALUE(ev_error) TYPE string.

  " P = prepare (no writes), E = execute the replacement of the layout with the token from prepare
  TRY.
      DATA(lo_form) = NEW zai_cl_adobe_form( ).
      CASE iv_mode.
        WHEN 'P'.
          DATA(ls_info) = lo_form->prepare_replace( iv_original     = iv_original
                                                    iv_copy         = iv_copy
                                                    iv_transport    = iv_transport
                                                    iv_check_author = xsdbool( iv_check_author = abap_true ) ).
          ev_form     = ls_info-form.
          ev_layout   = ls_info-layout.
          ev_token    = ls_info-token.
          ev_devclass = ls_info-devclass.
          ev_author   = ls_info-author.
          ev_lastuser = ls_info-lastuser.
          ev_tr_owner = ls_info-tr_owner.
        WHEN 'E'.
          ev_fm_name = lo_form->replace( iv_original     = iv_original
                                         iv_copy         = iv_copy
                                         iv_transport    = iv_transport
                                         iv_token        = iv_token
                                         iv_check_author = xsdbool( iv_check_author = abap_true ) ).
        WHEN OTHERS.
          ev_error = |Invalid mode { iv_mode }: use P (prepare) or E (execute)|.
      ENDCASE.
    CATCH zai_cx_adobe_form INTO DATA(lx_error).
      ev_error = lx_error->get_text( ).
  ENDTRY.
ENDFUNCTION.
