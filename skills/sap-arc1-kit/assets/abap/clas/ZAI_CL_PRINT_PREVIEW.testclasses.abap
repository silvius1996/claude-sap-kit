CLASS ltc_print_preview DEFINITION DEFERRED.
CLASS zai_cl_print_preview DEFINITION LOCAL FRIENDS ltc_print_preview.

" Harmless tests: no printing, no writes. Cases that depend on system data
" (BA00 messages, existing spool requests) end with a tolerable failure if missing
" (CL_ABAP_UNIT_ASSERT=>SKIP does not exist on 7.50).
CLASS ltc_print_preview DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zai_cl_print_preview.

    METHODS setup.
    METHODS no_message             FOR TESTING.
    METHODS short_document_number  FOR TESTING.
    METHODS missing_config         FOR TESTING.
    METHODS routine_not_found      FOR TESTING.
    METHODS spool_after_wraparound FOR TESTING.
    METHODS override_incomplete    FOR TESTING.
    METHODS override_form_missing  FOR TESTING.
    METHODS override_ok            FOR TESTING RAISING cx_static_check.
    METHODS form_kind              FOR TESTING.
    METHODS override_adobe_ok      FOR TESTING RAISING cx_static_check.
    METHODS program_not_allowed    FOR TESTING.
    METHODS unique_title           FOR TESTING.
ENDCLASS.


CLASS ltc_print_preview IMPLEMENTATION.
  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD no_message.
    TRY.
        mo_cut->read_message( iv_document    = '9999999999'
                              iv_output_type = 'BA00' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a document without message' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'No BA00 message for document*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD short_document_number.
    SELECT SINGLE objky FROM nast
      WHERE kappl = 'V1' AND kschl = 'BA00'
      INTO @DATA(lv_objky).
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg   = 'No BA00 message in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.
    DATA(lv_short) = CONV nast-objky( |{ lv_objky ALPHA = OUT }| ).

    TRY.
        DATA(ls_nast) = mo_cut->read_message( iv_document    = lv_short
                                              iv_output_type = 'BA00' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( lx_error->get_text( ) ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = ls_nast-objky
                                        exp = lv_objky ).
  ENDMETHOD.

  METHOD missing_config.
    " An output type without TNAPR entry: READ_CONFIG uses only KAPPL/KSCHL, so no NAST record
    " is needed (a join of NAST with TNAPR reads the whole NAST on systems with many messages)
    SELECT SINGLE @abap_true FROM tnapr
      WHERE kappl = 'V1'
        AND kschl = 'ZZZZ'
        AND nacha = '1'
      INTO @DATA(lv_exists).
    IF lv_exists = abap_true.
      cl_abap_unit_assert=>fail( msg   = 'Output type V1/ZZZZ has a TNAPR entry in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.

    TRY.
        mo_cut->read_config( VALUE #( kappl = 'V1' kschl = 'ZZZZ' ) ).
        cl_abap_unit_assert=>fail( 'Exception expected for an output type without TNAPR' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*has no print program*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD routine_not_found.
    DATA lv_rc TYPE sysubrc.
    TRY.
        CALL FUNCTION 'ZAI_PRINT_CALL_ROUTINE'
          EXPORTING
            is_nast       = VALUE nast( )
            is_tnapr      = VALUE tnapr( pgnam = 'RSPARAM'
                                         ronam = 'NOT_EXISTING' )
          IMPORTING
            ev_returncode = lv_rc.
        cl_abap_unit_assert=>fail( 'Exception expected for a missing routine' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = 'Routine NOT_EXISTING not found*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD spool_after_wraparound.
    " Spool number range wraps around: a preview spool request with a number below
    " the TSP01 maximum must still be found by title (previews delete their spool requests:
    " only those of older versions or kept with keepSpool are there)
    SELECT MAX( rqident ) FROM tsp01 INTO @DATA(lv_max).  "#EC CI_NOWHERE
    SELECT rqident, rqtitle FROM tsp01
      WHERE rqowner = @sy-uname
        AND rqtitle LIKE 'Claude preview%'
        AND rqident < @lv_max
      ORDER BY rqident DESCENDING
      INTO @DATA(ls_spool)
      UP TO 1 ROWS.                                     "#EC CI_NOFIELD
    ENDSELECT.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg   = 'No preview spool request below the TSP01 maximum'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.

    DATA(lt_spools) = mo_cut->find_spools( ls_spool-rqtitle ).

    cl_abap_unit_assert=>assert_true(
      act = xsdbool( line_exists( lt_spools[ rqident = ls_spool-rqident ] ) )
      msg = |Spool { ls_spool-rqident } not found by title| ).
  ENDMETHOD.

  METHOD override_incomplete.
    TRY.
        mo_cut->override_config( is_nast    = VALUE #( kappl = 'V2' kschl = 'LD00' )
                                 iv_form    = 'LE_SHP_DELNOTE'
                                 iv_program = ''
                                 iv_routine = '' ).
        cl_abap_unit_assert=>fail( 'Exception expected for an incomplete override' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*together*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD override_form_missing.
    TRY.
        mo_cut->override_config( is_nast    = VALUE #( kappl = 'V2' kschl = 'LD00' )
                                 iv_form    = 'ZAI_NOT_EXISTING'
                                 iv_program = 'RLE_DELNOTE'
                                 iv_routine = 'ENTRY' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a missing form' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*ZAI_NOT_EXISTING*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD override_ok.
    DATA(ls_tnapr) = mo_cut->override_config( is_nast    = VALUE #( kappl = 'V2' kschl = 'LD00' )
                                              iv_form    = 'LE_SHP_DELNOTE'
                                              iv_program = 'RLE_DELNOTE'
                                              iv_routine = 'ENTRY' ).
    cl_abap_unit_assert=>assert_equals( act = ls_tnapr-sform
                                        exp = 'LE_SHP_DELNOTE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_tnapr-pgnam
                                        exp = 'RLE_DELNOTE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_tnapr-kschl
                                        exp = 'LD00' ).
  ENDMETHOD.

  METHOD form_kind.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->form_kind( 'LE_SHP_DELNOTE' )
                                        exp = zai_cl_print_preview=>gc_kind_smartform ).
    cl_abap_unit_assert=>assert_initial( mo_cut->form_kind( 'ZAI_NOT_EXISTING' ) ).
  ENDMETHOD.

  METHOD override_adobe_ok.
    " FP_TEST_00 is the standard test form of transaction SFP; the program is only checked, not run
    IF mo_cut->form_kind( 'FP_TEST_00' ) <> zai_cl_print_preview=>gc_kind_adobe.
      cl_abap_unit_assert=>fail( msg   = 'Standard Adobe form FP_TEST_00 not found in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.
    DATA(ls_tnapr) = mo_cut->override_config( is_nast    = VALUE #( kappl = 'V1' kschl = 'BA00' )
                                              iv_form    = 'FP_TEST_00'
                                              iv_program = 'RLE_DELNOTE'
                                              iv_routine = 'ENTRY' ).
    cl_abap_unit_assert=>assert_equals( act = ls_tnapr-sform
                                        exp = 'FP_TEST_00' ).
    cl_abap_unit_assert=>assert_equals( act = ls_tnapr-formtype
                                        exp = zai_cl_print_preview=>gc_formtype_pdf ).
  ENDMETHOD.

  METHOD program_not_allowed.
    " A program that is not a print program configured in TNAPR: refused before anything runs
    SELECT SINGLE @abap_true FROM tnapr
      WHERE pgnam = 'RSPARAM'
      INTO @DATA(lv_configured).                        "#EC CI_NOFIELD
    SELECT SINGLE @abap_true FROM tvarvc
      WHERE name = @zai_cl_print_preview=>gc_allowed_programs
        AND low  = 'RSPARAM'
      INTO @DATA(lv_listed).                            "#EC CI_NOFIELD
    IF lv_configured = abap_true OR lv_listed = abap_true.
      cl_abap_unit_assert=>fail( msg   = 'RSPARAM is allowed as print program in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.
    TRY.
        mo_cut->override_config( is_nast    = VALUE #( kappl = 'V2' kschl = 'LD00' )
                                 iv_form    = 'LE_SHP_DELNOTE'
                                 iv_program = 'RSPARAM'
                                 iv_routine = 'ENTRY' ).
        cl_abap_unit_assert=>fail( 'Exception expected for a program not allowed' ).
      CATCH zai_cx_print_preview INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_char_cp( act = lx_error->get_text( )
                                             exp = '*RSPARAM*not allowed*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD unique_title.
    " Two previews in the same second took the same spool request when the title was made of date and time
    DATA(lv_first)  = mo_cut->new_title( 'BA00' ).
    DATA(lv_second) = mo_cut->new_title( 'BA00' ).
    cl_abap_unit_assert=>assert_differs( act = lv_second
                                         exp = lv_first ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_first
                                         exp = |{ zai_cl_print_preview=>gc_title_prefix } BA00 *| ).
  ENDMETHOD.
ENDCLASS.
