CLASS ltc_adobe_form DEFINITION DEFERRED.
CLASS zai_cl_adobe_form DEFINITION LOCAL FRIENDS ltc_adobe_form.

" Harmless tests: they read the standard test form FP_TEST_00 and check the refusals, without creating forms.
CLASS ltc_adobe_form DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS gc_standard TYPE fpname VALUE 'FP_TEST_00'.
    CONSTANTS gc_copy     TYPE fpname VALUE 'ZAI_AF_UNITTEST'.
    CONSTANTS gc_copy_if  TYPE fpname VALUE 'ZAI_AF_UNITTEST_IF'.

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
    METHODS renew_timestamp        FOR TESTING.
    METHODS renew_timestamp_added  FOR TESTING.
    METHODS interface_standard_refused FOR TESTING.
    METHODS interface_invalid_xml      FOR TESTING.
    METHODS interface_form_xml_refused FOR TESTING.
    METHODS normalize_ids              FOR TESTING RAISING cx_static_check.
    METHODS clear_cache_info           FOR TESTING RAISING cx_static_check.
    METHODS sort_texts                 FOR TESTING RAISING cx_static_check.
    METHODS replace_standard_refused   FOR TESTING.
    METHODS replace_copy_as_original   FOR TESTING.
    METHODS replace_copy_not_zai       FOR TESTING.
    METHODS replace_transport_missing  FOR TESTING.
    METHODS replace_task_refused       FOR TESTING.
    METHODS replace_other_author       FOR TESTING.

    "! The test form, or a tolerable failure if this system does not have it
    METHODS standard_form
      RETURNING VALUE(rs_form) TYPE zai_cl_adobe_form=>ty_form.

    METHODS assert_no_tadir
      IMPORTING iv_object TYPE trobjtype DEFAULT 'SFPF'
                iv_name   TYPE fpname    DEFAULT gc_copy.

    "! Refusal expected from prepare_replace, with a message matching the pattern
    METHODS assert_replace_refused
      IMPORTING iv_original     TYPE fpname
                iv_copy         TYPE fpname    DEFAULT gc_copy
                iv_transport    TYPE trkorr    DEFAULT 'DEVK999999'
                iv_check_author TYPE abap_bool DEFAULT abap_true
                iv_pattern      TYPE string.
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
      WHERE pgmid = 'R3TR' AND object = @iv_object AND obj_name = @iv_name
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

  METHOD renew_timestamp.
    " Only the timeStamp of the root changes: a changed layout must not reuse the ADS cache of the old one
    DATA(lv_xml) = cl_abap_codepage=>convert_from( mo_cut->renew_timestamp( cl_abap_codepage=>convert_to(
      `<?xml version="1.0"?><?xfa a="1"?><xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/" ` &&
      `timeStamp="2025-03-28T06:07:40Z" uuid="u1"><b timeStamp="keep"/></xdp:xdp>` ) ) ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_xml
      exp = `<?xml version="1.0"?><?xfa a="1"?><xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/" ` &&
            `timeStamp="2*Z" uuid="u1"><b timeStamp="keep"/></xdp:xdp>` ).
    cl_abap_unit_assert=>assert_char_np( act = lv_xml
                                         exp = '*2025-03-28T06:07:40Z*' ).
  ENDMETHOD.

  METHOD renew_timestamp_added.
    DATA(lv_xml) = cl_abap_codepage=>convert_from( mo_cut->renew_timestamp( cl_abap_codepage=>convert_to(
      `<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/"/>` ) ) ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_xml
                                         exp = `<xdp:xdp timeStamp="2*Z" xmlns:xdp="http://ns.adobe.com/xdp/"/>` ).
  ENDMETHOD.

  METHOD interface_standard_refused.
    TRY.
        mo_cut->write_interface( iv_name = 'SDOC_INTERFACE'
                                 iv_xml  = cl_abap_codepage=>convert_to( `<a/>` ) ).
        cl_abap_unit_assert=>fail( 'Write to a standard interface not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Writing allowed only for form interfaces*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD interface_invalid_xml.
    TRY.
        mo_cut->write_interface( iv_name = gc_copy_if
                                 iv_xml  = cl_abap_codepage=>convert_to( `not xml` ) ).
        cl_abap_unit_assert=>fail( 'Invalid interface XML not refused' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid*XML*' ).
    ENDTRY.
    assert_no_tadir( iv_object = 'SFPI' iv_name = gc_copy_if ).
  ENDMETHOD.

  METHOD interface_form_xml_refused.
    " The XML of a form is not an interface: nothing is written
    DATA(ls_form) = standard_form( ).
    TRY.
        mo_cut->write_interface( iv_name = gc_copy_if
                                 iv_xml  = ls_form-form ).
        cl_abap_unit_assert=>fail( 'Form XML accepted as interface' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid interface XML*' ).
    ENDTRY.
    assert_no_tadir( iv_object = 'SFPI' iv_name = gc_copy_if ).
  ENDMETHOD.

  METHOD normalize_ids.
    " Ids renumbered in document order, references following them: the same form gives the same XML
    DATA(li_document) = mo_cut->parse( cl_abap_codepage=>convert_to(
      `<a><b id="o17"/><c href="#o17"/><d id="o3"><e href="#o3"/><f href="#o17"/></d></a>` ) ).
    mo_cut->normalize_ids( li_document ).
    cl_abap_unit_assert=>assert_char_cp(
      act = cl_abap_codepage=>convert_from( mo_cut->render( ii_document = li_document
                                                            iv_pretty   = abap_false ) )
      " ## is a literal # in a CP pattern
      exp = `*<a><b id="o1"/><c href="##o1"/><d id="o2"><e href="##o2"/><f href="##o1"/></d></a>*` ).
  ENDMETHOD.

  METHOD clear_cache_info.
    DATA(li_document) = mo_cut->parse( cl_abap_codepage=>convert_to(
      `<a><CACHE_INFO>2026-10-19T16:52:37Z$x$0$en_US$v1.0$?</CACHE_INFO><b>1</b></a>` ) ).
    mo_cut->clear_cache_info( li_document ).
    cl_abap_unit_assert=>assert_char_cp(
      act = cl_abap_codepage=>convert_from( mo_cut->render( ii_document = li_document
                                                            iv_pretty   = abap_false ) )
      exp = `*<a><CACHE_INFO/><b>1</b></a>*` ).
  ENDMETHOD.

  METHOD sort_texts.
    " Texts of context and layout sorted by id and language, other elements untouched
    DATA(li_document) = mo_cut->parse( cl_abap_codepage=>convert_to(
      `<a><CONTEXTT><T><LANGUAGE>I</LANGUAGE><ID>B</ID></T><T><LANGUAGE>E</LANGUAGE><ID/></T>` &&
      `<T><LANGUAGE>D</LANGUAGE><ID>B</ID></T><T><LANGUAGE>D</LANGUAGE><ID/></T></CONTEXTT>` &&
      `<LAYOUTT><L><LANGUAGE>I</LANGUAGE></L><L><LANGUAGE>D</LANGUAGE></L></LAYOUTT><z>1</z><y>2</y></a>` ) ).
    mo_cut->sort_texts( li_document ).
    cl_abap_unit_assert=>assert_char_cp(
      act = cl_abap_codepage=>convert_from( mo_cut->render( ii_document = li_document
                                                            iv_pretty   = abap_false ) )
      exp = `*<a><CONTEXTT><T><LANGUAGE>D</LANGUAGE><ID/></T><T><LANGUAGE>E</LANGUAGE><ID/></T>` &&
            `<T><LANGUAGE>D</LANGUAGE><ID>B</ID></T><T><LANGUAGE>I</LANGUAGE><ID>B</ID></T></CONTEXTT>` &&
            `<LAYOUTT><L><LANGUAGE>D</LANGUAGE></L><L><LANGUAGE>I</LANGUAGE></L></LAYOUTT><z>1</z><y>2</y></a>*` ).
  ENDMETHOD.

  METHOD assert_replace_refused.
    TRY.
        mo_cut->prepare_replace( iv_original     = iv_original
                                 iv_copy         = iv_copy
                                 iv_transport    = iv_transport
                                 iv_check_author = iv_check_author ).
        cl_abap_unit_assert=>fail( |Replacement of { iv_original } with { iv_copy } in { iv_transport } not refused| ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = iv_pattern ).
    ENDTRY.
  ENDMETHOD.

  METHOD replace_standard_refused.
    assert_replace_refused( iv_original = gc_standard
                            iv_pattern  = 'Replacement allowed only*' ).
  ENDMETHOD.

  METHOD replace_copy_as_original.
    assert_replace_refused( iv_original = gc_copy
                            iv_copy     = 'ZAI_AF_UNITTEST2'
                            iv_pattern  = '*is a ZAI_* copy*' ).
  ENDMETHOD.

  METHOD replace_copy_not_zai.
    assert_replace_refused( iv_original = 'ZAF_UNITTEST'
                            iv_copy     = gc_standard
                            iv_pattern  = 'The copy must*' ).
  ENDMETHOD.

  METHOD replace_transport_missing.
    assert_replace_refused( iv_original  = 'ZAF_UNITTEST'
                            iv_transport = 'XXXK999999'
                            iv_pattern   = 'Transport request XXXK999999 does not exist' ).
  ENDMETHOD.

  METHOD replace_task_refused.
    " A task instead of its request: the message names the request
    SELECT trkorr, strkorr FROM e070
      WHERE strkorr <> ' '
        AND trstatus IN ('D','L')
      ORDER BY trkorr
      INTO @DATA(ls_task)
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg   = 'No open task in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.
    assert_replace_refused( iv_original  = 'ZAF_UNITTEST'
                            iv_transport = ls_task-trkorr
                            iv_pattern   = |*task of request { ls_task-strkorr }*| ).
  ENDMETHOD.

  METHOD replace_other_author.
    " Transportable Z*/Y* Adobe form of another user and an open workbench request
    SELECT obj_name FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'SFPF'
        AND ( obj_name LIKE 'Z%' OR obj_name LIKE 'Y%' )
        AND obj_name NOT LIKE 'ZAI\_%' ESCAPE '\'
        AND devclass <> '$TMP'
        AND devclass <> ' '
        AND author   <> @sy-uname
      ORDER BY obj_name
      INTO @DATA(lv_form)
      UP TO 1 ROWS
      BYPASSING BUFFER.
    ENDSELECT.
    SELECT trkorr FROM e070
      WHERE trfunction = 'K'
        AND trstatus   IN ('D','L')
        AND strkorr    = ' '
      ORDER BY trkorr
      INTO @DATA(lv_transport)
      UP TO 1 ROWS.
    ENDSELECT.
    IF lv_form IS INITIAL OR lv_transport IS INITIAL.
      cl_abap_unit_assert=>fail( msg   = 'No transportable Z*/Y* Adobe forms of other users or no open request'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.

    assert_replace_refused( iv_original  = CONV #( lv_form )
                            iv_transport = lv_transport
                            iv_pattern   = |*another user*{ sy-uname }*| ).

    " Check disabled (shared user): a later check refuses it, not the author one
    TRY.
        mo_cut->prepare_replace( iv_original     = CONV #( lv_form )
                                 iv_copy         = gc_copy
                                 iv_transport    = lv_transport
                                 iv_check_author = abap_false ).
        cl_abap_unit_assert=>fail( 'Missing copy accepted' ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_np( act = lx_error->get_text( )
                                             exp = '*another user*' ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
