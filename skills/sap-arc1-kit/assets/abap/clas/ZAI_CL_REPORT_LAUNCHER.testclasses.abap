CLASS ltc_launcher DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zai_cl_report_launcher.

    METHODS setup.
    METHODS executable_report_ok FOR TESTING RAISING cx_static_check.
    METHODS dialog_program_refused FOR TESTING.
    METHODS missing_program_refused FOR TESTING.
    METHODS report_tcode_resolved FOR TESTING RAISING cx_static_check.
    METHODS missing_tcode_refused FOR TESTING.
    METHODS run_without_report_refused FOR TESTING.
    METHODS run_dialog_tcode_refused FOR TESTING.
    METHODS run_missing_variant_refused FOR TESTING.
ENDCLASS.


CLASS ltc_launcher IMPLEMENTATION.
  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD executable_report_ok.
    mo_cut->check_report( 'RM07MLBS' ).
  ENDMETHOD.

  METHOD dialog_program_refused.
    TRY.
        mo_cut->check_report( 'SAPMV45A' ).
        cl_abap_unit_assert=>fail( 'A module pool must be refused' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD missing_program_refused.
    TRY.
        mo_cut->check_report( 'ZAI_NOT_EXISTING' ).
        cl_abap_unit_assert=>fail( 'A missing program must be refused' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD report_tcode_resolved.
    mo_cut->resolve_tcode( EXPORTING iv_tcode  = 'MB52'
                           IMPORTING ev_report = DATA(lv_report) ).
    cl_abap_unit_assert=>assert_equals( act = lv_report exp = 'RM07MLBS' ).
  ENDMETHOD.

  METHOD missing_tcode_refused.
    TRY.
        mo_cut->resolve_tcode( EXPORTING iv_tcode = 'ZAI_NO' ).
        cl_abap_unit_assert=>fail( 'A missing transaction must be refused' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD run_without_report_refused.
    TRY.
        mo_cut->run( ).
        cl_abap_unit_assert=>fail( 'Without report or transaction the run must fail' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD run_dialog_tcode_refused.
    TRY.
        mo_cut->run( iv_tcode = 'VA02' ).
        cl_abap_unit_assert=>fail( 'VA02 is a dialog transaction and must be refused' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD run_missing_variant_refused.
    TRY.
        mo_cut->run( iv_report = 'RM07MLBS' iv_variant = 'ZZ_NOT_EXIST' ).
        cl_abap_unit_assert=>fail( 'A missing variant must be refused' ).
      CATCH zai_cx_launcher ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
