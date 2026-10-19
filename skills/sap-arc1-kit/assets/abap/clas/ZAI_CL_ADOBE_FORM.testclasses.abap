CLASS ltc_adobe_form DEFINITION DEFERRED.
CLASS zai_cl_adobe_form DEFINITION LOCAL FRIENDS ltc_adobe_form.

" Harmless tests: they read the standard test form FP_TEST_00 and check the refusals, without creating forms.
CLASS ltc_adobe_form DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS gc_standard TYPE fpname VALUE 'FP_TEST_00'.
    CONSTANTS gc_copy     TYPE fpname VALUE 'ZAI_AF_UNITTEST'.

    DATA mo_cut TYPE REF TO zai_cl_adobe_form.

    METHODS setup.
    METHODS read_standard          FOR TESTING RAISING cx_static_check.
    METHODS read_missing           FOR TESTING.
    METHODS read_interface_missing FOR TESTING.
    METHODS parse_keeps_spaces     FOR TESTING RAISING cx_static_check.
    METHODS write_standard_refused FOR TESTING.
    METHODS write_without_layout   FOR TESTING.
    METHODS write_invalid_layout   FOR TESTING.
    METHODS write_invalid_xml      FOR TESTING.
    METHODS ads_available          FOR TESTING.

    "! The test form, or a tolerable failure if this system does not have it
    METHODS standard_form
      RETURNING VALUE(rs_form) TYPE zai_cl_adobe_form=>ty_form.

    METHODS assert_no_tadir.
ENDCLASS.


CLASS ltc_adobe_form IMPLEMENTATION.
  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD standard_form.
    SELECT SINGLE name FROM fplayout
      WHERE name  = @gc_standard
        AND state = 'A'
      INTO @DATA(lv_name).
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg   = |Standard Adobe form { gc_standard } not found in this system|
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.
    TRY.
        rs_form = mo_cut->read( lv_name ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD assert_no_tadir.
    SELECT SINGLE obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SFPF' AND obj_name = @gc_copy
      INTO @DATA(lv_tadir).
    cl_abap_unit_assert=>assert_subrc( exp = 4
                                       msg = |TADIR entry { lv_tadir } created by a refused write| ).
  ENDMETHOD.

  METHOD read_standard.
    DATA(ls_form) = standard_form( ).
    cl_abap_unit_assert=>assert_not_initial( act = ls_form-form
                                             msg = 'Form XML empty' ).
    " The layout is returned on its own, as XDP
    cl_abap_unit_assert=>assert_char_cp( act = cl_abap_codepage=>convert_from( ls_form-layout )
                                         exp = '*http://ns.adobe.com/xdp/*' ).
    " The form XML can be read back as it is written
    mo_cut->parse( ls_form-form ).
  ENDMETHOD.

  METHOD read_missing.
    TRY.
        mo_cut->read( 'ZAI_NOT_EXISTING' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a missing form' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*not found*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD read_interface_missing.
    TRY.
        mo_cut->read_interface( 'ZAI_NOT_EXISTING' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a missing interface' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*not found*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD parse_keeps_spaces.
    " The indentation between elements goes, the leading spaces of a text stay
    DATA(li_document) = mo_cut->parse( cl_abap_codepage=>convert_to(
      |<A>\n  <B>   x</B>\n  <C/>\n</A>| ) ).
    DATA(lv_xml) = cl_abap_codepage=>convert_from( mo_cut->render( ii_document = li_document
                                                                   iv_pretty   = abap_false ) ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_xml
                                         exp = '*<A><B>   x</B><C/></A>*' ).
  ENDMETHOD.

  METHOD write_standard_refused.
    TRY.
        mo_cut->write( iv_name   = gc_standard
                       iv_form   = cl_abap_codepage=>convert_to( `<a/>` )
                       iv_layout = cl_abap_codepage=>convert_to( `<a/>` ) ).
        cl_abap_unit_assert=>fail( 'Write to a standard form not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Writing allowed only*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD write_without_layout.
    TRY.
        mo_cut->write( iv_name   = gc_copy
                       iv_form   = cl_abap_codepage=>convert_to( `<a/>` )
                       iv_layout = VALUE #( ) ).
        cl_abap_unit_assert=>fail( 'Write without layout not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Layout (XDP) missing*' ).
    ENDTRY.
    assert_no_tadir( ).
  ENDMETHOD.

  METHOD write_invalid_layout.
    TRY.
        mo_cut->write( iv_name   = gc_copy
                       iv_form   = cl_abap_codepage=>convert_to( `<a/>` )
                       iv_layout = cl_abap_codepage=>convert_to( `<template/>` ) ).
        cl_abap_unit_assert=>fail( 'Layout without xdp root not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid layout*' ).
    ENDTRY.
    assert_no_tadir( ).
  ENDMETHOD.

  METHOD write_invalid_xml.
    TRY.
        mo_cut->write( iv_name   = gc_copy
                       iv_form   = cl_abap_codepage=>convert_to( `not xml` )
                       iv_layout = cl_abap_codepage=>convert_to( `<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/"/>` ) ).
        cl_abap_unit_assert=>fail( 'Invalid form XML not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid form XML*' ).
    ENDTRY.
    assert_no_tadir( ).
  ENDMETHOD.

  METHOD ads_available.
    " Not an error of the kit: without ADS the Adobe tools only read
    TRY.
        cl_abap_unit_assert=>assert_not_initial( mo_cut->ads_version( ) ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( msg   = |ADS not available in this system: { lx_error->get_text( ) }|
                                   level = if_aunit_constants=>tolerable ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
