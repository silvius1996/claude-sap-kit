CLASS zai_cl_print_preview DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_spool_ids TYPE STANDARD TABLE OF rspoid WITH EMPTY KEY.
    TYPES: BEGIN OF ty_result,
             pdf        TYPE xstring,
             spool_ids  TYPE tt_spool_ids,
             program    TYPE tnapr-pgnam,
             routine    TYPE tnapr-ronam,
             form       TYPE tnapr-sform,
             spool_type TYPE tsp01-rqdoctype,
           END OF ty_result.

    CONSTANTS gc_title_prefix TYPE string VALUE `Claude preview`.

    METHODS run
      IMPORTING iv_document      TYPE nast-objky
                iv_output_type   TYPE nast-kschl
                iv_application   TYPE nast-kappl OPTIONAL
                iv_language      TYPE nast-spras OPTIONAL
                iv_partner       TYPE nast-parnr OPTIONAL
                iv_device        TYPE nast-ldest DEFAULT 'LP01'
                iv_form          TYPE tdsfname OPTIONAL
                iv_program       TYPE progname OPTIONAL
                iv_routine       TYPE tnapr-ronam OPTIONAL
      RETURNING VALUE(rs_result) TYPE ty_result
      RAISING   zai_cx_print_preview.

    METHODS read_message
      IMPORTING iv_document    TYPE nast-objky
                iv_output_type TYPE nast-kschl
                iv_application TYPE nast-kappl OPTIONAL
                iv_language    TYPE nast-spras OPTIONAL
                iv_partner     TYPE nast-parnr OPTIONAL
      RETURNING VALUE(rs_nast) TYPE nast
      RAISING   zai_cx_print_preview.

    METHODS read_config
      IMPORTING is_nast         TYPE nast
      RETURNING VALUE(rs_tnapr) TYPE tnapr
      RAISING   zai_cx_print_preview.

    METHODS override_config
      IMPORTING is_nast         TYPE nast
                iv_form         TYPE tdsfname
                iv_program      TYPE progname
                iv_routine      TYPE tnapr-ronam
      RETURNING VALUE(rs_tnapr) TYPE tnapr
      RAISING   zai_cx_print_preview.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_spool,
             rqident   TYPE tsp01-rqident,
             rqdoctype TYPE tsp01-rqdoctype,
           END OF ty_spool,
           tt_spools TYPE STANDARD TABLE OF ty_spool WITH EMPTY KEY.

    METHODS prepare_nast
      IMPORTING is_nast        TYPE nast
                iv_device      TYPE nast-ldest
                iv_title       TYPE nast-tdcovtitle
      RETURNING VALUE(rs_nast) TYPE nast.

    METHODS find_spools
      IMPORTING iv_title         TYPE nast-tdcovtitle
      RETURNING VALUE(rt_spools) TYPE tt_spools.

    METHODS convert_to_pdf
      IMPORTING is_spool      TYPE ty_spool
      RETURNING VALUE(rv_pdf) TYPE xstring
      RAISING   zai_cx_print_preview.
ENDCLASS.


CLASS zai_cl_print_preview IMPLEMENTATION.
  METHOD run.
    DATA(ls_nast)  = read_message( iv_document    = iv_document
                                   iv_output_type = iv_output_type
                                   iv_application = iv_application
                                   iv_language    = iv_language
                                   iv_partner     = iv_partner ).
    DATA(ls_tnapr) = COND tnapr( WHEN iv_form IS INITIAL AND iv_program IS INITIAL AND iv_routine IS INITIAL
                                 THEN read_config( ls_nast )
                                 ELSE override_config( is_nast    = ls_nast
                                                       iv_form    = iv_form
                                                       iv_program = iv_program
                                                       iv_routine = iv_routine ) ).

    DATA(lv_title) = CONV nast-tdcovtitle( |{ gc_title_prefix } { sy-datum }{ sy-uzeit } { ls_nast-kschl }| ).
    DATA lv_returncode TYPE sysubrc.

    CALL FUNCTION 'ZAI_PRINT_CALL_ROUTINE'
      EXPORTING
        is_nast       = prepare_nast( is_nast   = ls_nast
                                      iv_device = iv_device
                                      iv_title  = lv_title )
        is_tnapr      = ls_tnapr
      IMPORTING
        ev_returncode = lv_returncode.

    IF lv_returncode <> 0.
      DATA(lv_message) = COND string( WHEN sy-msgid IS NOT INITIAL
                                      THEN |{ sy-msgid } { sy-msgno }: { sy-msgv1 } { sy-msgv2 } { sy-msgv3 } { sy-msgv4 }| ).
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |Print program { ls_tnapr-pgnam } failed (return code { lv_returncode }) { lv_message }| ).
    ENDIF.

    DATA(lt_spools) = find_spools( lv_title ).
    IF lt_spools IS INITIAL.
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |Print program { ls_tnapr-pgnam } created no spool request| ).
    ENDIF.

    DATA(ls_first) = lt_spools[ 1 ].
    rs_result = VALUE #( pdf        = convert_to_pdf( ls_first )
                         spool_ids  = VALUE #( FOR ls_spool IN lt_spools ( ls_spool-rqident ) )
                         program    = ls_tnapr-pgnam
                         routine    = ls_tnapr-ronam
                         form       = ls_tnapr-sform
                         spool_type = ls_first-rqdoctype ).
  ENDMETHOD.

  METHOD read_message.
    TYPES tt_kappl TYPE RANGE OF nast-kappl.
    TYPES tt_spras TYPE RANGE OF nast-spras.
    TYPES tt_parnr TYPE RANGE OF nast-parnr.

    " Purely numeric document numbers: pad with leading zeros (VBELN, 10 characters)
    DATA(lv_objky) = COND nast-objky(
      WHEN condense( iv_document ) CO '0123456789'
      THEN |{ CONV vbeln( condense( iv_document ) ) ALPHA = IN }|
      ELSE iv_document ).

    DATA(lt_kappl) = COND tt_kappl( WHEN iv_application IS NOT INITIAL
                                    THEN VALUE #( ( sign = 'I' option = 'EQ' low = iv_application ) ) ).
    DATA(lt_spras) = COND tt_spras( WHEN iv_language IS NOT INITIAL
                                    THEN VALUE #( ( sign = 'I' option = 'EQ' low = iv_language ) ) ).
    DATA(lt_parnr) = COND tt_parnr( WHEN iv_partner IS NOT INITIAL
                                    THEN VALUE #( ( sign = 'I' option = 'EQ' low = iv_partner ) ) ).

    " Full record: the print program uses the whole NAST structure
    SELECT * FROM nast                                  "#EC CI_ALL_FIELDS_NEEDED
      WHERE kappl IN @lt_kappl
        AND objky =  @lv_objky
        AND kschl =  @iv_output_type
        AND spras IN @lt_spras
        AND parnr IN @lt_parnr
      ORDER BY erdat DESCENDING, eruhr DESCENDING
      INTO @rs_nast
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |No { iv_output_type } message for document { lv_objky ALPHA = OUT }| ).
    ENDIF.
  ENDMETHOD.

  METHOD read_config.
    SELECT SINGLE kappl, kschl, nacha, pgnam, ronam, fonam, sform, formtype, funcname
      FROM tnapr
      WHERE kappl = @is_nast-kappl
        AND kschl = @is_nast-kschl
        AND nacha = '1'
      INTO CORRESPONDING FIELDS OF @rs_tnapr.
    IF sy-subrc <> 0 OR rs_tnapr-pgnam IS INITIAL OR rs_tnapr-ronam IS INITIAL.
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |Output type { is_nast-kappl }/{ is_nast-kschl } has no print program configured (TNAPR)| ).
    ENDIF.
  ENDMETHOD.

  METHOD override_config.
    IF iv_form IS INITIAL OR iv_program IS INITIAL OR iv_routine IS INITIAL.
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |Replacing the form requires form, program and routine together| ).
    ENDIF.

    SELECT SINGLE name FROM progdir
      WHERE name  = @iv_program
        AND state = 'A'
      INTO @DATA(lv_program).
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zai_cx_print_preview( iv_text = |Print program { iv_program } does not exist or is not active| ).
    ENDIF.

    DATA lv_fm_name TYPE rs38l_fnam.
    CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
      EXPORTING
        formname           = iv_form
      IMPORTING
        fm_name            = lv_fm_name
      EXCEPTIONS
        no_form            = 1
        no_function_module = 2
        OTHERS             = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zai_cx_print_preview( iv_text = |SmartForms { iv_form } does not exist or is not active| ).
    ENDIF.

    " Configuration in memory only: TNAPR is neither read nor written
    rs_tnapr = VALUE #( kappl = is_nast-kappl
                        kschl = is_nast-kschl
                        nacha = '1'
                        pgnam = lv_program
                        ronam = iv_routine
                        sform = iv_form ).
  ENDMETHOD.

  METHOD prepare_nast.
    " Copy in memory only: output to spool, no immediate printing and no archiving
    rs_nast            = is_nast.
    rs_nast-nacha      = '1'.
    rs_nast-ldest      = iv_device.
    rs_nast-dimme      = space.
    rs_nast-delet      = space.
    rs_nast-tdarmod    = '1'.
    rs_nast-tdcovtitle = iv_title.
    rs_nast-anzal      = 1.
  ENDMETHOD.

  METHOD find_spools.
    " No filter on RQIDENT: the number range SPO_NUM wraps around (100-32000),
    " so a new spool request can have a lower number than the existing ones.
    " The title contains date and time and is unique per run.
    SELECT rqident, rqdoctype
      FROM tsp01
      WHERE rqowner = @sy-uname
        AND rqtitle = @iv_title
      ORDER BY rqident
      INTO TABLE @rt_spools.                            "#EC CI_NOFIELD
    IF sy-subrc <> 0.
      CLEAR rt_spools.
    ENDIF.
  ENDMETHOD.

  METHOD convert_to_pdf.
    CASE is_spool-rqdoctype.
      WHEN 'ADSP'.
        CALL FUNCTION 'FPCOMP_CREATE_PDF_FROM_SPOOL'
          EXPORTING
            i_spoolid      = is_spool-rqident
            i_partnum      = 1
          IMPORTING
            e_pdf          = rv_pdf
          EXCEPTIONS
            ads_error      = 1
            usage_error    = 2
            system_error   = 3
            internal_error = 4
            OTHERS         = 5.
      WHEN 'OTF' OR 'SMART'.
        CALL FUNCTION 'CONVERT_OTFSPOOLJOB_2_PDF'
          EXPORTING
            src_spoolid           = is_spool-rqident
            no_dialog             = abap_true
            no_background         = abap_true
            pdf_destination       = 'X'
          IMPORTING
            bin_file              = rv_pdf
          EXCEPTIONS
            err_no_otf_spooljob   = 1
            err_no_spooljob       = 2
            err_no_permission     = 3
            err_conv_not_possible = 4
            OTHERS                = 5.
      WHEN 'LIST'.
        CALL FUNCTION 'CONVERT_ABAPSPOOLJOB_2_PDF'
          EXPORTING
            src_spoolid     = is_spool-rqident
            no_dialog       = abap_true
            no_background   = abap_true
            pdf_destination = 'X'
          IMPORTING
            bin_file        = rv_pdf
          EXCEPTIONS
            OTHERS          = 1.
      WHEN OTHERS.
        RAISE EXCEPTION NEW zai_cx_print_preview(
          iv_text = |Spool { is_spool-rqident }: type { is_spool-rqdoctype } cannot be converted to PDF| ).
    ENDCASE.

    IF sy-subrc <> 0 OR rv_pdf IS INITIAL.
      RAISE EXCEPTION NEW zai_cx_print_preview(
        iv_text = |Conversion of spool { is_spool-rqident } ({ is_spool-rqdoctype }) to PDF failed, return code { sy-subrc }| ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
