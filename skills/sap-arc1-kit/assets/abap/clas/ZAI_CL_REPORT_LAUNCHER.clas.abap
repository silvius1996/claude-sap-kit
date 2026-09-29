"! Runs an executable report (by name or transaction) with a variant and/or
"! selection values, without screen output, and captures the result:
"! ALV data serialized as JSON or the classic list as text.
CLASS zai_cl_report_launcher DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF gc_output,
        alv  TYPE char4 VALUE 'ALV',
        list TYPE char4 VALUE 'LIST',
        none TYPE char4 VALUE 'NONE',
      END OF gc_output.

    TYPES:
      BEGIN OF ty_result,
        report      TYPE progname,
        variant     TYPE raldb_vari,
        output_type TYPE char4,
        row_count   TYPE i,
        data_json   TYPE string,
        list        TYPE string_table,
      END OF ty_result.

    TYPES:
      BEGIN OF ty_variant,
        variant    TYPE raldb_vari,
        text       TYPE varit-vtext,
        changed_by TYPE varid-aename,
        changed_on TYPE varid-aedat,
      END OF ty_variant,
      ty_variants TYPE STANDARD TABLE OF ty_variant WITH EMPTY KEY.

    "! Runs the report. Either the report or the transaction is required.
    "! The values in it_params override the variant values.
    METHODS run
      IMPORTING
        iv_report        TYPE progname OPTIONAL
        iv_tcode         TYPE tcode OPTIONAL
        iv_variant       TYPE raldb_vari OPTIONAL
        it_params        TYPE rsparams_tt OPTIONAL
      RETURNING
        VALUE(rs_result) TYPE ty_result
      RAISING
        zai_cx_launcher.

    METHODS get_variants
      IMPORTING
        iv_report          TYPE progname
      RETURNING
        VALUE(rt_variants) TYPE ty_variants.

    METHODS get_variant_contents
      IMPORTING
        iv_report        TYPE progname
        iv_variant       TYPE raldb_vari
      RETURNING
        VALUE(rt_params) TYPE rsparams_tt
      RAISING
        zai_cx_launcher.

    "! Resolves the transaction to its report (and variant, if the
    "! transaction has one) and checks the authorization.
    METHODS resolve_tcode
      IMPORTING
        iv_tcode   TYPE tcode
      EXPORTING
        ev_report  TYPE progname
        ev_variant TYPE raldb_vari
      RAISING
        zai_cx_launcher.

    "! Checks that the program exists and is an executable report (SUBC = 1).
    METHODS check_report
      IMPORTING
        iv_report TYPE progname
      RAISING
        zai_cx_launcher.

  PRIVATE SECTION.
    METHODS check_variant
      IMPORTING
        iv_report  TYPE progname
        iv_variant TYPE raldb_vari
      RAISING
        zai_cx_launcher.

    METHODS submit_report
      IMPORTING
        iv_report  TYPE progname
        iv_variant TYPE raldb_vari
        it_params  TYPE rsparams_tt.

    METHODS capture_alv
      CHANGING
        cs_result TYPE ty_result.

    METHODS capture_list
      CHANGING
        cs_result TYPE ty_result.
ENDCLASS.


CLASS zai_cl_report_launcher IMPLEMENTATION.
  METHOD run.
    DATA(lv_report)  = iv_report.
    DATA(lv_variant) = iv_variant.

    IF iv_tcode IS NOT INITIAL.
      resolve_tcode( EXPORTING iv_tcode   = iv_tcode
                     IMPORTING ev_report  = lv_report
                               ev_variant = DATA(lv_tcode_variant) ).
      IF lv_variant IS INITIAL.
        lv_variant = lv_tcode_variant.
      ENDIF.
    ENDIF.

    IF lv_report IS INITIAL.
      RAISE EXCEPTION TYPE zai_cx_launcher EXPORTING iv_text = |Specify a report or a transaction|.
    ENDIF.

    check_report( lv_report ).
    IF lv_variant IS NOT INITIAL.
      check_variant( iv_report = lv_report iv_variant = lv_variant ).
    ENDIF.

    rs_result = VALUE #( report      = lv_report
                         variant     = lv_variant
                         output_type = gc_output-none ).

    cl_salv_bs_runtime_info=>set( display  = abap_false
                                  metadata = abap_false
                                  data     = abap_true ).
    submit_report( iv_report = lv_report iv_variant = lv_variant it_params = it_params ).

    capture_alv( CHANGING cs_result = rs_result ).
    cl_salv_bs_runtime_info=>clear_all( ).

    IF rs_result-output_type = gc_output-none.
      capture_list( CHANGING cs_result = rs_result ).
    ENDIF.
    CALL FUNCTION 'LIST_FREE_MEMORY'.
  ENDMETHOD.

  METHOD get_variants.
    SELECT variant, aename AS changed_by, aedat AS changed_on
      FROM varid
      WHERE report = @iv_report
      INTO CORRESPONDING FIELDS OF TABLE @rt_variants.
    " Sorted here: ORDER BY in the SELECT would bypass the table buffer of VARID
    SORT rt_variants BY variant.

    SELECT variant, vtext
      FROM varit
      WHERE report = @iv_report
        AND langu  = @sy-langu
      INTO TABLE @DATA(lt_texts).

    LOOP AT rt_variants ASSIGNING FIELD-SYMBOL(<ls_variant>).
      <ls_variant>-text = VALUE #( lt_texts[ variant = <ls_variant>-variant ]-vtext OPTIONAL ).
    ENDLOOP.
  ENDMETHOD.

  METHOD get_variant_contents.
    check_variant( iv_report = iv_report iv_variant = iv_variant ).

    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report               = iv_report
        variant              = iv_variant
      TABLES
        valutab              = rt_params
      EXCEPTIONS
        variant_non_existent = 1
        variant_obsolete     = 2
        OTHERS               = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_launcher
        EXPORTING
          iv_text = |Cannot read variant { iv_variant } of { iv_report } (sy-subrc { sy-subrc })|.
    ENDIF.
  ENDMETHOD.

  METHOD resolve_tcode.
    CLEAR: ev_report, ev_variant.

    SELECT SINGLE pgmna FROM tstc
      WHERE tcode = @iv_tcode
      INTO @ev_report.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_launcher EXPORTING iv_text = |Transaction { iv_tcode } does not exist|.
    ENDIF.

    CALL FUNCTION 'AUTHORITY_CHECK_TCODE'
      EXPORTING
        tcode  = iv_tcode
      EXCEPTIONS
        ok     = 0
        not_ok = 1
        OTHERS = 2.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_launcher EXPORTING iv_text = |No authorization for transaction { iv_tcode }|.
    ENDIF.

    " Report transactions with a variant: report and variant are in the parameters
    SELECT SINGLE param FROM tstcp
      WHERE tcode = @iv_tcode
      INTO @DATA(lv_param).
    IF sy-subrc = 0.
      FIND REGEX `D_SREPOVARI-REPORT=([^;]+)` IN lv_param SUBMATCHES DATA(lv_report).
      IF sy-subrc = 0.
        ev_report = condense( lv_report ).
      ENDIF.
      FIND REGEX `D_SREPOVARI-VARIANT=([^;]+)` IN lv_param SUBMATCHES DATA(lv_variant).
      IF sy-subrc = 0.
        ev_variant = condense( lv_variant ).
      ENDIF.
    ENDIF.

    IF ev_report IS INITIAL.
      RAISE EXCEPTION TYPE zai_cx_launcher EXPORTING iv_text = |Transaction { iv_tcode } is not linked to a report|.
    ENDIF.
  ENDMETHOD.

  METHOD check_report.
    SELECT SINGLE subc FROM trdir
      WHERE name = @iv_report
      INTO @DATA(lv_subc).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_launcher EXPORTING iv_text = |Program { iv_report } does not exist|.
    ENDIF.
    IF lv_subc <> '1'.
      RAISE EXCEPTION TYPE zai_cx_launcher
        EXPORTING
          iv_text = |{ iv_report } is not an executable report (type { lv_subc }): dialog programs cannot be run|.
    ENDIF.
  ENDMETHOD.

  METHOD check_variant.
    SELECT SINGLE @abap_true FROM varid
      WHERE report  = @iv_report
        AND variant = @iv_variant
      INTO @DATA(lv_exists).
    IF lv_exists = abap_false.
      RAISE EXCEPTION TYPE zai_cx_launcher
        EXPORTING
          iv_text = |Variant { iv_variant } does not exist for { iv_report } in client { sy-mandt }|.
    ENDIF.
  ENDMETHOD.

  METHOD submit_report.
    IF iv_variant IS INITIAL.
      SUBMIT (iv_report)
        WITH SELECTION-TABLE it_params
        EXPORTING LIST TO MEMORY
        AND RETURN.
    ELSE.
      SUBMIT (iv_report)
        USING SELECTION-SET iv_variant
        WITH SELECTION-TABLE it_params
        EXPORTING LIST TO MEMORY
        AND RETURN.
    ENDIF.
  ENDMETHOD.

  METHOD capture_alv.
    DATA lr_data TYPE REF TO data.
    FIELD-SYMBOLS <lt_data> TYPE ANY TABLE.

    TRY.
        cl_salv_bs_runtime_info=>get_data_ref( IMPORTING r_data = lr_data ).
      CATCH cx_salv_bs_sc_runtime_info.
        RETURN.
    ENDTRY.
    IF lr_data IS NOT BOUND.
      RETURN.
    ENDIF.

    ASSIGN lr_data->* TO <lt_data>.
    cs_result-output_type = gc_output-alv.
    cs_result-row_count   = lines( <lt_data> ).
    cs_result-data_json   = /ui2/cl_json=>serialize( data        = <lt_data>
                                                     pretty_name = /ui2/cl_json=>pretty_mode-none ).
  ENDMETHOD.

  METHOD capture_list.
    TYPES ty_line TYPE c LENGTH 2048.
    DATA: lt_abaplist TYPE STANDARD TABLE OF abaplist,
          lt_ascii    TYPE STANDARD TABLE OF ty_line.

    CALL FUNCTION 'LIST_FROM_MEMORY'
      TABLES
        listobject = lt_abaplist
      EXCEPTIONS
        not_found  = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    CALL FUNCTION 'LIST_TO_ASCI'
      TABLES
        listasci           = lt_ascii
        listobject         = lt_abaplist
      EXCEPTIONS
        empty_list         = 1
        list_index_invalid = 2
        OTHERS             = 3.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    cs_result-output_type = gc_output-list.
    cs_result-list        = VALUE #( FOR lv_line IN lt_ascii ( CONV string( lv_line ) ) ).
    cs_result-row_count   = lines( cs_result-list ).
  ENDMETHOD.
ENDCLASS.
