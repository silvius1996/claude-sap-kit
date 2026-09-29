CLASS ltc_smartform_xml DEFINITION DEFERRED.
CLASS zai_cl_smartform_xml DEFINITION LOCAL FRIENDS ltc_smartform_xml.

" Harmless tests: they read the standard form LE_SHP_DELNOTE and check the refusals, without creating forms.
CLASS ltc_smartform_xml DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zai_cl_smartform_xml.

    METHODS setup.
    METHODS read_standard           FOR TESTING RAISING cx_static_check.
    METHODS read_with_namespaces    FOR TESTING RAISING cx_static_check.
    METHODS read_missing            FOR TESTING.
    METHODS check_accepts_warnings  FOR TESTING RAISING cx_static_check.
    METHODS parse_keeps_spaces      FOR TESTING RAISING cx_static_check.
    METHODS parse_without_header    FOR TESTING.
    METHODS write_standard_refused  FOR TESTING.
    METHODS write_invalid_xml       FOR TESTING.
    METHODS write_without_namespace FOR TESTING.
    METHODS replace_standard_refused  FOR TESTING.
    METHODS replace_copy_as_original  FOR TESTING.
    METHODS replace_copy_not_zai      FOR TESTING.
    METHODS replace_transport_missing FOR TESTING.
    METHODS replace_other_author      FOR TESTING RAISING cx_static_check.

    "! Transportable Z*/Y* form of another user and an open workbench request; empty if the system has none
    METHODS other_author_data
      EXPORTING ev_form      TYPE tdsfname
                ev_transport TYPE trkorr.
ENDCLASS.


CLASS ltc_smartform_xml IMPLEMENTATION.
  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD read_standard.
    DATA(lv_xml) = cl_abap_codepage=>convert_from( mo_cut->read( 'LE_SHP_DELNOTE' ) ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_xml
                                         exp = '*SMARTFORM*' ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_xml
                                         exp = '*LE_SHP_DELNOTE*' ).
  ENDMETHOD.

  METHOD read_with_namespaces.
    " XML_UPLOAD recognizes the nodes by namespace only: without declarations the uploaded form stays empty
    DATA(li_ixml)     = cl_ixml=>create( ).
    DATA(li_factory)  = li_ixml->create_stream_factory( ).
    DATA(li_document) = li_ixml->create_document( ).
    li_ixml->create_parser( stream_factory = li_factory
                            istream        = li_factory->create_istream_xstring( mo_cut->read( 'LE_SHP_DELNOTE' ) )
                            document       = li_document )->parse( ).
    DATA(li_root) = li_document->get_root_element( ).

    cl_abap_unit_assert=>assert_equals( act = li_root->get_namespace_uri( )
                                        exp = `urn:sap-com:SmartForms:2000:internal-structure` ).
    cl_abap_unit_assert=>assert_not_initial( act = li_root->get_attribute( name      = 'language'
                                                                           namespace = 'sf' )
                                             msg = 'Attribute sf:language missing' ).
    DATA(li_header) = li_root->find_from_name_ns( name = 'HEADER'
                                                  uri  = `urn:sap-com:sdixml-ifr:2000` ).
    cl_abap_unit_assert=>assert_bound( act = li_header
                                       msg = 'HEADER without ifr namespace' ).
  ENDMETHOD.

  METHOD read_missing.
    TRY.
        mo_cut->read( 'ZAI_NOT_EXISTING' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a missing form' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*not found*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD check_accepts_warnings.
    " The active standard form only gives warnings in the global check: as in transaction SMARTFORMS, they must not block
    SELECT SINGLE masterlang FROM stxfadm
      WHERE formname = 'LE_SHP_DELNOTE'
      INTO @DATA(lv_language).
    DATA(lo_form) = NEW cl_ssf_fb_smart_form( ).
    lo_form->load( im_formname = 'LE_SHP_DELNOTE'
                   im_language = lv_language ).
    mo_cut->check_form( lo_form ).
  ENDMETHOD.

  METHOD parse_keeps_spaces.
    " Leading spaces of code and texts must be kept; the indentation between elements must not,
    " because XML_UPLOAD reads the first child node as an element in several places
    DATA(li_root) = mo_cut->parse( cl_abap_codepage=>convert_to(
      |<sf:SMARTFORM xmlns:sf="urn:sap-com:SmartForms:2000:internal-structure" xmlns="urn:sap-com:sdixml-ifr:2000">\n| &&
      | <HEADER>   IF X.</HEADER>\n| &&
      |</sf:SMARTFORM>| ) ).

    cl_abap_unit_assert=>assert_equals( act = li_root->num_children( )
                                        exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = li_root->get_first_child( )->get_value( )
                                        exp = `   IF X.` ).
  ENDMETHOD.

  METHOD parse_without_header.
    " Correct namespaces but no content: XML_UPLOAD and CHECK would accept it as an empty form
    TRY.
        mo_cut->parse( cl_abap_codepage=>convert_to(
          `<sf:SMARTFORM xmlns:sf="urn:sap-com:SmartForms:2000:internal-structure" xmlns="urn:sap-com:sdixml-ifr:2000"/>` ) ).
        cl_abap_unit_assert=>fail( 'XML without HEADER not refused' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid XML*HEADER*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD write_standard_refused.
    TRY.
        mo_cut->write( iv_name = 'LE_SHP_DELNOTE'
                       iv_xml  = cl_abap_codepage=>convert_to( `<x/>` ) ).
        cl_abap_unit_assert=>fail( 'Write to a standard form not refused' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Writing allowed only*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD write_invalid_xml.
    TRY.
        mo_cut->write( iv_name = 'ZAI_SF_UNITTEST'
                       iv_xml  = cl_abap_codepage=>convert_to( `not xml` ) ).
        cl_abap_unit_assert=>fail( 'Invalid XML not refused' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid XML*' ).
    ENDTRY.
    SELECT SINGLE obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SSFO' AND obj_name = 'ZAI_SF_UNITTEST'
      INTO @DATA(lv_tadir).
    cl_abap_unit_assert=>assert_subrc( exp = 4
                                       msg = |TADIR entry { lv_tadir } created despite invalid XML| ).
  ENDMETHOD.

  METHOD write_without_namespace.
    TRY.
        mo_cut->write( iv_name = 'ZAI_SF_UNITTEST'
                       iv_xml  = cl_abap_codepage=>convert_to( `<SMARTFORM><HEADER/></SMARTFORM>` ) ).
        cl_abap_unit_assert=>fail( 'XML without SmartForms namespace not refused' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Invalid XML*namespace*' ).
    ENDTRY.
    SELECT SINGLE obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SSFO' AND obj_name = 'ZAI_SF_UNITTEST'
      INTO @DATA(lv_tadir).
    cl_abap_unit_assert=>assert_subrc( exp = 4
                                       msg = |TADIR entry { lv_tadir } created despite XML without namespace| ).
  ENDMETHOD.

  METHOD replace_standard_refused.
    TRY.
        mo_cut->prepare_replace( iv_original  = 'LE_SHP_DELNOTE'
                                 iv_copy      = 'ZAI_SF_UNITTEST'
                                 iv_transport = 'DEVK999999' ).
        cl_abap_unit_assert=>fail( 'Replacement of a standard form not refused' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Replacement allowed only*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD replace_copy_as_original.
    TRY.
        mo_cut->prepare_replace( iv_original  = 'ZAI_SF_UNITTEST'
                                 iv_copy      = 'ZAI_SF_UNITTEST2'
                                 iv_transport = 'DEVK999999' ).
        cl_abap_unit_assert=>fail( 'ZAI_* copy accepted as original' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*is a ZAI_* copy*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD replace_copy_not_zai.
    TRY.
        mo_cut->prepare_replace( iv_original  = 'ZSF_UNITTEST'
                                 iv_copy      = 'LE_SHP_DELNOTE'
                                 iv_transport = 'DEVK999999' ).
        cl_abap_unit_assert=>fail( 'Non-ZAI_* copy accepted' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'The copy must*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD replace_transport_missing.
    TRY.
        mo_cut->prepare_replace( iv_original  = 'ZSF_UNITTEST'
                                 iv_copy      = 'ZAI_SF_UNITTEST'
                                 iv_transport = 'XXXK999999' ).
        cl_abap_unit_assert=>fail( 'Missing transport request accepted' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Transport request XXXK999999*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD replace_other_author.
    other_author_data( IMPORTING ev_form      = DATA(lv_form)
                                 ev_transport = DATA(lv_transport) ).
    IF lv_form IS INITIAL OR lv_transport IS INITIAL.
      cl_abap_unit_assert=>fail( msg   = 'No transportable Z*/Y* SmartForms of other users or no open request'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.

    " Check active: refused with the logged-on user
    TRY.
        mo_cut->prepare_replace( iv_original  = lv_form
                                 iv_copy      = 'ZAI_SF_UNITTEST'
                                 iv_transport = lv_transport ).
        cl_abap_unit_assert=>fail( 'Form of another user accepted' ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = |*another user*{ sy-uname }*| ).
    ENDTRY.

    " Check disabled (shared user): the next check is reached, the missing copy
    TRY.
        mo_cut->prepare_replace( iv_original     = lv_form
                                 iv_copy         = 'ZAI_SF_UNITTEST'
                                 iv_transport    = lv_transport
                                 iv_check_author = abap_false ).
        cl_abap_unit_assert=>fail( 'Missing copy accepted' ).
      CATCH zai_cx_smartform INTO lx_error.
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Copy ZAI_SF_UNITTEST not found' ).
    ENDTRY.
  ENDMETHOD.

  METHOD other_author_data.
    " Generic search for the test: the single-record buffer of TADIR is not needed
    SELECT obj_name FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'SSFO'
        AND ( obj_name LIKE 'Z%' OR obj_name LIKE 'Y%' )
        AND obj_name NOT LIKE 'ZAI\_%' ESCAPE '\'
        AND devclass <> '$TMP'
        AND devclass <> ' '
        AND author   <> @sy-uname
      ORDER BY obj_name
      INTO @ev_form
      UP TO 1 ROWS
      BYPASSING BUFFER.
    ENDSELECT.
    SELECT trkorr FROM e070
      WHERE trfunction = 'K'
        AND trstatus   IN ('D','L')
      ORDER BY trkorr
      INTO @ev_transport
      UP TO 1 ROWS.
    ENDSELECT.
  ENDMETHOD.
ENDCLASS.
