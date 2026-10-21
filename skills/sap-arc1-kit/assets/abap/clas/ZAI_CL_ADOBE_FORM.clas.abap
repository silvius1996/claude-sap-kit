"! Reads and writes Adobe forms (transaction SFP) with the SAP APIs used by abapGit: the form as XML
"! without its layout, the layout as XDP and the form interface as XML. Writing is limited to local
"! ZAI_* forms ($TMP) of the current user. The SAP API updates the layout of a loaded form in place
"! (LOAD in WRITE mode, SET_LAYOUT_DATA, SAVE) but cannot replace its context, so an existing ZAI_* copy
"! is deleted and created again; customer and standard forms are never written or deleted.
"! Form interfaces ZAI_* are created, or updated in place with the setters of the loaded interface: the forms
"! that use them stay linked.
CLASS zai_cl_adobe_form DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_form,
             form   TYPE xstring,
             layout TYPE xstring,
           END OF ty_form.

    TYPES: BEGIN OF ty_write_result,
             fm_name     TYPE rs38l_fnam,
             created     TYPE abap_bool,
             ads_version TYPE string,
           END OF ty_write_result.

    "! Name pattern of writable forms
    CONSTANTS gc_writable_pattern TYPE string VALUE `ZAI_*`.

    "! Form XML without layout (one element per line) and layout XDP (as stored)
    METHODS read
      IMPORTING iv_name        TYPE fpname
      RETURNING VALUE(rs_form) TYPE ty_form
      RAISING   zai_cx_adobe_form.

    METHODS read_interface
      IMPORTING iv_name       TYPE fpname
      RETURNING VALUE(rv_xml) TYPE xstring
      RAISING   zai_cx_adobe_form.

    METHODS write
      IMPORTING iv_name          TYPE fpname
                iv_form          TYPE xstring
                iv_layout        TYPE xstring
      RETURNING VALUE(rs_result) TYPE ty_write_result
      RAISING   zai_cx_adobe_form.

    "! Interface XML (as returned by read_interface) written as ZAI_* interface in $TMP and activated:
    "! created if it does not exist, otherwise updated in place
    METHODS write_interface
      IMPORTING iv_name           TYPE fpname
                iv_xml            TYPE xstring
      RETURNING VALUE(rv_created) TYPE abap_bool
      RAISING   zai_cx_adobe_form.

    "! Version of Adobe Document Services; exception if ADS is not configured
    METHODS ads_version
      RETURNING VALUE(rv_version) TYPE string
      RAISING   zai_cx_adobe_form.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_target,
             object_exists TYPE abap_bool,
             tadir_exists  TYPE abap_bool,
           END OF ty_target.

    CONSTANTS gc_xdp_namespace   TYPE string VALUE `http://ns.adobe.com/xdp/`.
    CONSTANTS gc_object_form      TYPE trobjtype VALUE 'SFPF'.
    CONSTANTS gc_object_interface TYPE trobjtype VALUE 'SFPI'.

    METHODS check_target
      IMPORTING iv_name          TYPE fpname
                iv_object        TYPE trobjtype DEFAULT gc_object_form
      RETURNING VALUE(rs_target) TYPE ty_target
      RAISING   zai_cx_adobe_form.

    METHODS tadir_exists
      IMPORTING iv_name          TYPE fpname
                iv_object        TYPE trobjtype DEFAULT gc_object_form
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    METHODS to_interface
      IMPORTING iv_xml              TYPE xstring
      RETURNING VALUE(ri_interface) TYPE REF TO if_fp_interface
      RAISING   zai_cx_adobe_form.

    METHODS update_interface
      IMPORTING iv_name      TYPE fpname
                ii_interface TYPE REF TO if_fp_interface
      RAISING   zai_cx_adobe_form.

    METHODS create_interface
      IMPORTING iv_name      TYPE fpname
                ii_interface TYPE REF TO if_fp_interface
      RAISING   zai_cx_adobe_form.

    "! Parameters, global definitions, coding and reference fields
    METHODS copy_interface_data
      IMPORTING ii_from TYPE REF TO if_fp_interface_data
                ii_to   TYPE REF TO if_fp_interface_data.

    "! Parses the XML and removes the indentation between elements
    METHODS parse
      IMPORTING iv_xml             TYPE xstring
      RETURNING VALUE(ri_document) TYPE REF TO if_ixml_document
      RAISING   zai_cx_adobe_form.

    METHODS render
      IMPORTING ii_document   TYPE REF TO if_ixml_document
                iv_pretty     TYPE abap_bool
      RETURNING VALUE(rv_xml) TYPE xstring.

    "! One element per line, so that the file stays editable line by line; unchanged if it is not XML
    METHODS pretty_print
      IMPORTING iv_xml        TYPE xstring
      RETURNING VALUE(rv_xml) TYPE xstring.

    METHODS check_layout
      IMPORTING iv_layout TYPE xstring
      RAISING   zai_cx_adobe_form.

    METHODS to_form
      IMPORTING iv_form        TYPE xstring
                iv_layout      TYPE xstring
      RETURNING VALUE(ri_form) TYPE REF TO if_fp_form
      RAISING   zai_cx_adobe_form.

    METHODS delete_copy
      IMPORTING iv_name TYPE fpname
      RAISING   zai_cx_adobe_form.

    METHODS tadir_entry
      IMPORTING iv_name   TYPE fpname
                iv_object TYPE trobjtype DEFAULT gc_object_form
                iv_delete TYPE abap_bool DEFAULT abap_false
      RAISING   zai_cx_adobe_form.

    METHODS create_and_save
      IMPORTING iv_name TYPE fpname
                ii_form TYPE REF TO if_fp_form
      RAISING   zai_cx_adobe_form.

    METHODS activate
      IMPORTING iv_name   TYPE fpname
                iv_object TYPE trobjtype DEFAULT gc_object_form
      RAISING   zai_cx_adobe_form.

    METHODS function_module
      IMPORTING iv_name           TYPE fpname
      RETURNING VALUE(rv_fm_name) TYPE rs38l_fnam
      RAISING   zai_cx_adobe_form.
    "! New timeStamp on the xdp element, as LiveCycle Designer does when saving
    METHODS renew_timestamp
      IMPORTING iv_layout        TYPE xstring
      RETURNING VALUE(rv_layout) TYPE xstring.
ENDCLASS.


CLASS zai_cl_adobe_form IMPLEMENTATION.
  METHOD read.
    CONSTANTS lc_no_layout TYPE xstring VALUE ''.
    DATA li_form    TYPE REF TO if_fp_form.
    DATA lx_convert TYPE REF TO cx_fp_api.

    SELECT SINGLE name FROM fplayout
      WHERE name  = @iv_name
        AND state = 'A'
      INTO @DATA(lv_name).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form EXPORTING iv_text = |Adobe form { iv_name } not found or not active|.
    ENDIF.

    TRY.
        DATA(li_wb_form) = cl_fp_wb_form=>load( lv_name ).
        li_form ?= li_wb_form->get_object( ).
        DATA(li_layout) = li_form->get_layout( ).
        rs_form-layout = li_layout->get_layout_data( ).
      CATCH cx_fp_api INTO DATA(lx_load).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe form { iv_name } cannot be read: { lx_load->get_text( ) }|
            previous = lx_load.
    ENDTRY.

    " As in abapGit: the layout is taken out of the form XML and returned as a file of its own.
    " The form object is changed in memory only and never saved.
    TRY.
        li_layout->set_layout_data( i_layout_data   = lc_no_layout
                                    i_set_xliff_ids = abap_false ).
        TRY.
            rs_form-form = cl_fp_helper=>convert_form_to_xstring( li_form ).
          CATCH cx_fp_api INTO lx_convert ##NO_HANDLER.
            " Raised below, after the layout is back in place
        ENDTRY.
        li_layout->set_layout_data( i_layout_data   = rs_form-layout
                                    i_set_xliff_ids = abap_false ).
      CATCH cx_fp_api INTO DATA(lx_layout).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe form { iv_name }: layout not separated from the form: { lx_layout->get_text( ) }|
            previous = lx_layout.
    ENDTRY.
    TRY.
        li_wb_form->free( ).
      CATCH cx_fp_api ##NO_HANDLER.
        " Only releases the object loaded for display: the form is already read
    ENDTRY.

    IF lx_convert IS BOUND.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text  = |Adobe form { iv_name } not converted to XML: { lx_convert->get_text( ) }|
          previous = lx_convert.
    ENDIF.
    rs_form-form = pretty_print( rs_form-form ).
  ENDMETHOD.

  METHOD read_interface.
    DATA li_interface TYPE REF TO if_fp_interface.

    SELECT SINGLE name FROM fpinterface
      WHERE name  = @iv_name
        AND state = 'A'
      INTO @DATA(lv_name).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form EXPORTING iv_text = |Form interface { iv_name } not found or not active|.
    ENDIF.

    TRY.
        DATA(li_wb_interface) = cl_fp_wb_interface=>load( lv_name ).
        li_interface ?= li_wb_interface->get_object( ).
        rv_xml = cl_fp_helper=>convert_interface_to_xstring( li_interface ).
        li_wb_interface->free( ).
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Form interface { iv_name } cannot be read: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
    rv_xml = pretty_print( rv_xml ).
  ENDMETHOD.

  METHOD write.
    " All checks before any change in the system
    DATA(ls_target) = check_target( iv_name ).
    IF iv_layout IS INITIAL.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Layout (XDP) missing: an Adobe form is written together with its layout|.
    ENDIF.
    check_layout( iv_layout ).
    DATA(li_form) = to_form( iv_form   = render( ii_document = parse( iv_form )
                                                 iv_pretty   = abap_false )
                             iv_layout = renew_timestamp( iv_layout ) ).
    " As in abapGit: without ADS a form is not saved
    rs_result-ads_version = ads_version( ).

    " The context cannot be replaced in place: the own copy is deleted and created again (the tool saves a backup first)
    IF ls_target-object_exists = abap_true.
      delete_copy( iv_name ).
    ENDIF.
    DATA(lv_new_tadir) = xsdbool( tadir_exists( iv_name ) = abap_false ).
    IF lv_new_tadir = abap_true.
      tadir_entry( iv_name ).
    ENDIF.

    TRY.
        create_and_save( iv_name = iv_name
                         ii_form = li_form ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        " The TADIR entry created here must not be left orphaned
        IF lv_new_tadir = abap_true.
          TRY.
              tadir_entry( iv_name   = iv_name
                           iv_delete = abap_true ).
            CATCH zai_cx_adobe_form ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = lx_error->get_text( ) &&
                       COND #( WHEN ls_target-object_exists = abap_true
                               THEN ` (the previous version of the copy was already deleted: upload the backup again)` )
            previous = lx_error.
    ENDTRY.

    activate( iv_name ).
    rs_result-fm_name = function_module( iv_name ).
    rs_result-created = xsdbool( ls_target-object_exists = abap_false ).
  ENDMETHOD.

  METHOD write_interface.
    " All checks before any change in the system
    DATA(ls_target) = check_target( iv_name   = iv_name
                                    iv_object = gc_object_interface ).
    DATA(li_interface) = to_interface( iv_xml ).
    IF li_interface->get_interface_type( ) = if_fp_interface=>c_interface_type_xsd.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Form interface { iv_name }: XML schema based interfaces are not supported|.
    ENDIF.

    IF ls_target-object_exists = abap_true.
      update_interface( iv_name      = iv_name
                        ii_interface = li_interface ).
    ELSE.
      DATA(lv_new_tadir) = xsdbool( ls_target-tadir_exists = abap_false ).
      IF lv_new_tadir = abap_true.
        tadir_entry( iv_name   = iv_name
                     iv_object = gc_object_interface ).
      ENDIF.
      TRY.
          create_interface( iv_name      = iv_name
                            ii_interface = li_interface ).
        CATCH zai_cx_adobe_form INTO DATA(lx_error).
          " The TADIR entry created here must not be left orphaned
          IF lv_new_tadir = abap_true.
            TRY.
                tadir_entry( iv_name   = iv_name
                             iv_object = gc_object_interface
                             iv_delete = abap_true ).
              CATCH zai_cx_adobe_form ##NO_HANDLER.
            ENDTRY.
          ENDIF.
          RAISE EXCEPTION lx_error.
      ENDTRY.
    ENDIF.

    activate( iv_name   = iv_name
              iv_object = gc_object_interface ).
    rv_created = xsdbool( ls_target-object_exists = abap_false ).
  ENDMETHOD.

  METHOD to_interface.
    " The XML of a form also has an INTERFACE element, with the name only: the interface object has a reference
    DATA(li_document) = parse( iv_xml ).
    DATA(li_root) = li_document->find_from_name( name = 'INTERFACE' ).
    IF li_root IS NOT BOUND OR li_root->get_attribute( 'href' ) IS INITIAL.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Invalid interface XML: not the XML of a form interface (use Custom_AdobeFormRead)|.
    ENDIF.
    TRY.
        ri_interface = cl_fp_helper=>convert_xstring_to_interface( render( ii_document = li_document
                                                                           iv_pretty   = abap_false ) ).
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Invalid interface XML: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
    IF ri_interface IS NOT BOUND.
      RAISE EXCEPTION TYPE zai_cx_adobe_form EXPORTING iv_text = |Invalid interface XML: no form interface found|.
    ENDIF.
  ENDMETHOD.

  METHOD update_interface.
    " In place: the forms that use the interface stay linked to it
    DATA li_current TYPE REF TO if_fp_interface.
    TRY.
        DATA(li_wb_interface) = cl_fp_wb_interface=>load( i_name = iv_name
                                                          i_mode = if_fp_wb_object=>c_mode_write ).
        li_current ?= li_wb_interface->get_object( ).
        IF li_current->get_interface_type( ) <> ii_interface->get_interface_type( ).
          li_wb_interface->free( ).
          RAISE EXCEPTION TYPE zai_cx_adobe_form
            EXPORTING
              iv_text = |Form interface { iv_name }: the interface type cannot be changed | &&
                        |({ li_current->get_interface_type( ) } -> { ii_interface->get_interface_type( ) })|.
        ENDIF.
        copy_interface_data( ii_from = ii_interface->get_interface_data( )
                             ii_to   = li_current->get_interface_data( ) ).
        li_wb_interface->save( ).
        li_wb_interface->free( ).
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Form interface { iv_name } not updated: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD create_interface.
    DATA lv_transport TYPE trkorr.
    TRY.
        DATA(li_wb_interface) = cl_fp_wb_interface=>create( i_name      = iv_name
                                                            i_interface = ii_interface
                                                            i_ordernum  = lv_transport ).
        li_wb_interface->save( ).
        li_wb_interface->free( ).
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Form interface { iv_name } not saved: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD copy_interface_data.
    DATA(li_from_parameters) = ii_from->get_parameters( ).
    DATA(li_to_parameters)   = ii_to->get_parameters( ).
    li_to_parameters->set_import_parameters( li_from_parameters->get_import_parameters( ) ).
    li_to_parameters->set_export_parameters( li_from_parameters->get_export_parameters( ) ).
    li_to_parameters->set_table_parameters( li_from_parameters->get_table_parameters( ) ).
    li_to_parameters->set_exceptions( li_from_parameters->get_exceptions( ) ).

    DATA(li_from_globals) = ii_from->get_global_definitions( ).
    DATA(li_to_globals)   = ii_to->get_global_definitions( ).
    li_to_globals->set_types( li_from_globals->get_types( ) ).
    li_to_globals->set_global_data( li_from_globals->get_global_data( ) ).
    li_to_globals->set_fieldsymbols( li_from_globals->get_fieldsymbols( ) ).

    DATA(li_from_coding) = ii_from->get_coding( ).
    DATA(li_to_coding)   = ii_to->get_coding( ).
    li_to_coding->set_init_input_params( li_from_coding->get_init_input_params( ) ).
    li_to_coding->set_init_output_params( li_from_coding->get_init_output_params( ) ).
    li_to_coding->set_init_coding( li_from_coding->get_init_coding( ) ).
    li_to_coding->set_forms_coding( li_from_coding->get_forms_coding( ) ).

    ii_to->get_reference_fields( )->set_reference_fields( ii_from->get_reference_fields( )->get_reference_fields( ) ).
  ENDMETHOD.

  METHOD ads_version.
    TRY.
        rv_version = cl_fp=>get_reference( )->create_pdf_object( connection = cl_fp=>get_ads_connection( )
                                           )->get_version_info( ).
      CATCH cx_root INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe Document Services (ADS) not reachable: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
    IF rv_version IS INITIAL.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Adobe Document Services (ADS) not configured: Adobe forms cannot be saved or printed|.
    ENDIF.
  ENDMETHOD.

  METHOD check_target.
    DATA(lv_kind) = COND string( WHEN iv_object = gc_object_interface THEN `Form interface` ELSE `Adobe form` ).
    IF iv_name NP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Writing allowed only for { COND string( WHEN iv_object = gc_object_interface
                                                             THEN `form interfaces` ELSE `Adobe forms` ) } | &&
                    |{ gc_writable_pattern }: { iv_name } refused|.
    ENDIF.

    SELECT SINGLE devclass, author FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = @iv_object
        AND obj_name = @iv_name
      INTO @DATA(ls_tadir).
    IF sy-subrc = 0.
      IF ls_tadir-devclass <> '$TMP' OR ls_tadir-author <> sy-uname.
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text = |{ lv_kind } { iv_name } cannot be changed: package { ls_tadir-devclass }, author { ls_tadir-author }|.
      ENDIF.
      rs_target-tadir_exists = abap_true.
    ENDIF.

    " Any version, active or not
    DATA lv_name TYPE fpname.
    IF iv_object = gc_object_interface.
      SELECT SINGLE name FROM fpinterface
        WHERE name = @iv_name
        INTO @lv_name.
    ELSE.
      SELECT SINGLE name FROM fplayout
        WHERE name = @iv_name
        INTO @lv_name.
    ENDIF.
    rs_target-object_exists = xsdbool( sy-subrc = 0 ).
    " Without object directory entry the object is not a copy of the kit: it is never changed
    IF rs_target-object_exists = abap_true AND rs_target-tadir_exists = abap_false.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ lv_kind } { lv_name } exists without object directory entry: not changed|.
    ENDIF.
  ENDMETHOD.

  METHOD tadir_exists.
    SELECT SINGLE @abap_true FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = @iv_object
        AND obj_name = @iv_name
      INTO @rv_exists.
  ENDMETHOD.

  METHOD parse.
    DATA lt_indentation TYPE STANDARD TABLE OF REF TO if_ixml_node WITH EMPTY KEY.

    DATA(li_ixml)    = cl_ixml=>create( ).
    DATA(li_factory) = li_ixml->create_stream_factory( ).
    ri_document = li_ixml->create_document( ).
    DATA(li_parser) = li_ixml->create_parser( stream_factory = li_factory
                                              istream        = li_factory->create_istream_xstring( iv_xml )
                                              document       = ri_document ).
    " Normalizing would strip the leading spaces of texts and code
    li_parser->set_normalizing( abap_false ).
    IF li_parser->parse( ) <> 0.
      DATA(li_parse_error) = li_parser->get_error( index = 0 ).
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Invalid form XML: { COND #( WHEN li_parse_error IS BOUND THEN li_parse_error->get_reason( ) ) }|.
    ENDIF.
    IF ri_document->get_root_element( ) IS NOT BOUND.
      RAISE EXCEPTION TYPE zai_cx_adobe_form EXPORTING iv_text = |Invalid form XML: root element missing|.
    ENDIF.

    " Only the indentation between elements, as added by pretty_print
    DATA(li_iterator) = ri_document->create_iterator( ).
    DATA(li_node)     = li_iterator->get_next( ).
    WHILE li_node IS BOUND.
      IF li_node->get_type( ) = if_ixml_node=>co_node_text
         AND li_node->get_parent( )->num_children( ) > 1
         AND matches( val   = li_node->get_value( )
                      regex = `[[:space:]]*` ).
        APPEND li_node TO lt_indentation.
      ENDIF.
      li_node = li_iterator->get_next( ).
    ENDWHILE.
    LOOP AT lt_indentation INTO li_node.
      li_node->remove_node( ).
    ENDLOOP.
  ENDMETHOD.

  METHOD render.
    DATA(li_ixml)   = cl_ixml=>create( ).
    DATA(li_stream) = li_ixml->create_stream_factory( )->create_ostream_xstring( string = rv_xml ).
    li_stream->set_pretty_print( iv_pretty ).
    li_ixml->create_renderer( ostream  = li_stream
                              document = ii_document )->render( ).
  ENDMETHOD.

  METHOD pretty_print.
    TRY.
        rv_xml = render( ii_document = parse( iv_xml )
                         iv_pretty   = abap_true ).
      CATCH zai_cx_adobe_form.
        rv_xml = iv_xml.
    ENDTRY.
  ENDMETHOD.

  METHOD check_layout.
    " Parsed only to check it: the layout is passed to SAP unchanged
    DATA(li_ixml)     = cl_ixml=>create( ).
    DATA(li_factory)  = li_ixml->create_stream_factory( ).
    DATA(li_document) = li_ixml->create_document( ).
    DATA(li_parser)   = li_ixml->create_parser( stream_factory = li_factory
                                                istream        = li_factory->create_istream_xstring( iv_layout )
                                                document       = li_document ).
    li_parser->set_normalizing( abap_false ).
    IF li_parser->parse( ) <> 0.
      DATA(li_parse_error) = li_parser->get_error( index = 0 ).
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Invalid layout (XDP): { COND #( WHEN li_parse_error IS BOUND THEN li_parse_error->get_reason( ) ) }|.
    ENDIF.
    DATA(li_root) = li_document->get_root_element( ).
    IF li_root IS NOT BOUND OR li_root->get_name( ) <> 'xdp' OR li_root->get_namespace_uri( ) <> gc_xdp_namespace.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Invalid layout: root element xdp with namespace { gc_xdp_namespace } missing|.
    ENDIF.
  ENDMETHOD.

  METHOD to_form.
    TRY.
        ri_form = cl_fp_helper=>convert_xstring_to_form( iv_form ).
      CATCH cx_fp_api INTO DATA(lx_form).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Invalid form XML: { lx_form->get_text( ) }|
            previous = lx_form.
    ENDTRY.
    TRY.
        ri_form->get_layout( )->set_layout_data( iv_layout ).
      CATCH cx_fp_api INTO DATA(lx_layout).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Layout not accepted: { lx_layout->get_text( ) }|
            previous = lx_layout.
    ENDTRY.
  ENDMETHOD.

  METHOD delete_copy.
    DATA lv_transport TYPE trkorr.
    TRY.
        TRY.
            " I_DARK (no popups) exists after 7.40; static call as in abapGit for older releases
            CALL METHOD cl_fp_wb_form=>('DELETE')
              EXPORTING
                i_name     = iv_name
                i_ordernum = lv_transport
                i_dark     = abap_true.
          CATCH cx_sy_dyn_call_error.
            cl_fp_wb_form=>delete( i_name     = iv_name
                                   i_ordernum = lv_transport ).
        ENDTRY.
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Copy { iv_name } not rewritten: its previous version cannot be deleted: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD tadir_entry.
    " Object directory entry in $TMP created before the form: CREATE finds the local package
    " and does not ask for a transport request
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus         = space
        wi_delete_tadir_entry = iv_delete
        wi_tadir_pgmid        = 'R3TR'
        wi_tadir_object       = iv_object
        wi_tadir_obj_name     = CONV sobj_name( iv_name )
        wi_tadir_devclass     = COND devclass( WHEN iv_delete = abap_false THEN '$TMP' )
      EXCEPTIONS
        OTHERS                = 1.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |TADIR entry for { iv_name } not { COND #( WHEN iv_delete = abap_true THEN `removed` ELSE `created` ) }: | &&
                    |{ sy-msgid } { sy-msgno } { sy-msgv1 }|.
    ENDIF.
  ENDMETHOD.

  METHOD create_and_save.
    DATA li_wb_form   TYPE REF TO if_fp_wb_form.
    DATA lv_transport TYPE trkorr.
    TRY.
        TRY.
            CALL METHOD cl_fp_wb_form=>('CREATE')
              EXPORTING
                i_name     = iv_name
                i_form     = ii_form
                i_ordernum = lv_transport
                i_dark     = abap_true
              RECEIVING
                r_wb_form  = li_wb_form.
          CATCH cx_sy_dyn_call_error.
            li_wb_form = cl_fp_wb_form=>create( i_name     = iv_name
                                                i_form     = ii_form
                                                i_ordernum = lv_transport ).
        ENDTRY.
        li_wb_form->save( ).
        li_wb_form->free( ).
      CATCH cx_fp_api INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe form { iv_name } not saved: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD activate.
    DATA lt_objects TYPE STANDARD TABLE OF dwinactiv WITH DEFAULT KEY.
    lt_objects = VALUE #( ( object = iv_object obj_name = iv_name ) ).

    " Same call as abapGit; UI_DECOUPLED does not exist on every release
    TRY.
        CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
          EXPORTING
            activate_ddic_objects  = abap_false
            with_popup             = abap_false
            ui_decoupled           = abap_true
          TABLES
            objects                = lt_objects
          EXCEPTIONS
            excecution_error       = 1
            cancelled              = 2
            insert_into_corr_error = 3
            OTHERS                 = 4.
      CATCH cx_sy_dyn_call_param_not_found.
        CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
          EXPORTING
            activate_ddic_objects  = abap_false
            with_popup             = abap_false
          TABLES
            objects                = lt_objects
          EXCEPTIONS
            excecution_error       = 1
            cancelled              = 2
            insert_into_corr_error = 3
            OTHERS                 = 4.
    ENDTRY.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ iv_object } { iv_name } saved but not activated (return code { sy-subrc }): | &&
                    |{ sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 }|.
    ENDIF.
  ENDMETHOD.

  METHOD function_module.
    DATA lx_error TYPE REF TO cx_root.
    TRY.
        CALL FUNCTION 'FP_FUNCTION_MODULE_NAME'
          EXPORTING
            i_name     = iv_name
          IMPORTING
            e_funcname = rv_fm_name.
      CATCH cx_fp_api_repository cx_fp_api_usage cx_fp_api_internal INTO lx_error.
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe form { iv_name } active but function module not available: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD renew_timestamp.
    " ADS caches the template under timeStamp and uuid of the xdp element (form CACHE_INFO): a changed
    " layout with the old timeStamp is printed as before. Only the root start tag changes, the rest
    " stays byte for byte (the root was checked by check_layout)
    DATA lv_now TYPE timestamp.
    DATA(lv_xml) = cl_abap_codepage=>convert_from( iv_layout ).
    FIND FIRST OCCURRENCE OF REGEX `<[^?!][^>]*>` IN lv_xml MATCH OFFSET DATA(lv_offset) MATCH LENGTH DATA(lv_length).
    IF sy-subrc <> 0.
      rv_layout = iv_layout.
      RETURN.
    ENDIF.
    GET TIME STAMP FIELD lv_now.
    DATA(lv_stamp) = |timeStamp="{ lv_now TIMESTAMP = ISO }Z"|.
    DATA(lv_tag)   = substring( val = lv_xml off = lv_offset len = lv_length ).
    REPLACE FIRST OCCURRENCE OF REGEX `timeStamp="[^"]*"` IN lv_tag WITH lv_stamp.
    IF sy-subrc <> 0.
      REPLACE FIRST OCCURRENCE OF REGEX `^(<[^[:space:]/>]+)` IN lv_tag WITH `$1 ` && lv_stamp.
    ENDIF.
    rv_layout = cl_abap_codepage=>convert_to( substring( val = lv_xml len = lv_offset ) && lv_tag &&
                                              substring( val = lv_xml off = lv_offset + lv_length ) ).
  ENDMETHOD.
ENDCLASS.
