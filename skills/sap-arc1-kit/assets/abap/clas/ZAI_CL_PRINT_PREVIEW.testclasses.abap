CLASS ltc_print_preview DEFINITION DEFERRED.
CLASS zai_cl_print_preview DEFINITION LOCAL FRIENDS ltc_print_preview.

" Harmless tests: no printing, no writes. Cases that depend on system data
" (BA00 messages, output types without TNAPR, existing spool requests) end with a tolerable
" warning if missing (CL_ABAP_UNIT_ASSERT=>SKIP does not exist on 7.50).
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
    " A print message (medium 1) whose output type has no TNAPR entry
    SELECT n~kappl, n~kschl, n~objky
      FROM nast AS n
      LEFT OUTER JOIN tnapr AS t ON  t~kappl = n~kappl
                                 AND t~kschl = n~kschl
                                 AND t~nacha = '1'
      WHERE n~nacha = '1'
        AND t~kschl IS NULL
      INTO @DATA(ls_candidate)
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg   = 'No message without TNAPR in this system'
                                 level = if_aunit_constants=>tolerable
                                 quit  = if_aunit_constants=>method ).
    ENDIF.

    TRY.
        mo_cut->read_config( VALUE #( kappl = ls_candidate-kappl kschl = ls_candidate-kschl ) ).
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
    " the TSP01 maximum must still be found by title
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
ENDCLASS.
