"! Reads and writes Adobe forms (transaction SFP) with the SAP APIs used by abapGit: the form as XML
"! without its layout, the layout as XDP and the form interface as XML. Writing is limited to local
"! ZAI_* forms ($TMP) of the current user. The SAP API updates the layout of a loaded form in place
"! (LOAD in WRITE mode, SET_LAYOUT_DATA, SAVE) but cannot replace its context, so an existing ZAI_* copy
"! is deleted and created again; customer and standard forms are never written or deleted.
"! Form interfaces ZAI_* are created, or updated in place with the setters of the loaded interface: the forms
"! that use them stay linked. A customer form Z*/Y* gets the layout of an approved ZAI_* copy through
"! prepare_replace/replace, in place and under a transport request, only when the rest of the form is unchanged.
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

    TYPES: BEGIN OF ty_replace_info,
             devclass    TYPE devclass,
             author      TYPE responsibl,
             lastuser    TYPE syuname,
             language    TYPE sylangu,
             tr_owner    TYPE as4user,
             token       TYPE string,
             "! Original form XML and layout, for the backup
             form        TYPE xstring,
             layout      TYPE xstring,
             copy_layout TYPE xstring,
           END OF ty_replace_info.

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

    "! Checks and data to give a customer form the layout of a ZAI_* copy; no writes
    METHODS prepare_replace
      IMPORTING iv_original     TYPE fpname
                iv_copy         TYPE fpname
                iv_transport    TYPE trkorr
                iv_check_author TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rs_info)  TYPE ty_replace_info
      RAISING   zai_cx_adobe_form.

    "! Writes the layout of the copy into the original, in place, and records the original in the request;
    "! the token must come from prepare_replace
    METHODS replace
      IMPORTING iv_original       TYPE fpname
                iv_copy           TYPE fpname
                iv_transport      TYPE trkorr
                iv_token          TYPE string
                iv_check_author   TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv_fm_name) TYPE rs38l_fnam
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

    "! One element per line, so that the file stays editable line by line, with object ids renumbered and
    "! CACHE_INFO empty, so that the same form always gives the same XML; unchanged if it is not XML
    METHODS pretty_print
      IMPORTING iv_xml        TYPE xstring
      RETURNING VALUE(rv_xml) TYPE xstring.

    "! As abapGit (fix_oref): object ids o<n> renumbered in document order, with their references #o<n>
    METHODS normalize_ids
      IMPORTING ii_document TYPE REF TO if_ixml_document.

    "! As abapGit: CACHE_INFO depends on the layout (timeStamp, uuid) and SAP computes it again when saving
    METHODS clear_cache_info
      IMPORTING ii_document TYPE REF TO if_ixml_document.

    METHODS check_replace
      IMPORTING iv_original     TYPE fpname
                iv_copy         TYPE fpname
                iv_transport    TYPE trkorr
                iv_check_author TYPE abap_bool
      RETURNING VALUE(rs_info)  TYPE ty_replace_info
      RAISING   zai_cx_adobe_form.

    "! Owner of a modifiable workbench request; a task is refused with the name of its request
    METHODS check_transport
      IMPORTING iv_transport    TYPE trkorr
      RETURNING VALUE(rv_owner) TYPE as4user
      RAISING   zai_cx_adobe_form.

    "! SHA1 of form XML and layout: any change to the form changes it
    METHODS fingerprint
      IMPORTING is_form        TYPE ty_form
      RETURNING VALUE(rv_hash) TYPE string
      RAISING   zai_cx_adobe_form.

    METHODS corr_insert
      IMPORTING iv_name      TYPE fpname
                iv_devclass  TYPE devclass
                iv_language  TYPE sylangu
                iv_transport TYPE trkorr
      RAISING   zai_cx_adobe_form.

    "! Layout written in place into the loaded form (WRITE mode): context and interface stay as they are
    METHODS replace_layout
      IMPORTING iv_name   TYPE fpname
                iv_layout TYPE xstring
      RAISING   zai_cx_adobe_form.

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
        DATA(li_document) = parse( iv_xml ).
      CATCH zai_cx_adobe_form.
        rv_xml = iv_xml.
        RETURN.
    ENDTRY.
    normalize_ids( li_document ).
    clear_cache_info( li_document ).
    rv_xml = render( ii_document = li_document
                     iv_pretty   = abap_true ).
  ENDMETHOD.

  METHOD normalize_ids.
    " The ids change at every conversion to XML; the references are collected first, by their old value
    TYPES: BEGIN OF ty_href,
             value     TYPE string,
             attribute TYPE REF TO if_ixml_attribute,
           END OF ty_href.
    DATA lt_hrefs   TYPE SORTED TABLE OF ty_href WITH NON-UNIQUE KEY value.
    DATA li_element TYPE REF TO if_ixml_element.
    DATA lv_count   TYPE i.

    DATA(li_iterator) = ii_document->create_iterator_filtered(
      ii_document->create_filter_and( filter1 = ii_document->create_filter_node_type( if_ixml_node=>co_node_element )
                                      filter2 = ii_document->create_filter_attribute( 'href' ) ) ).
    li_element ?= li_iterator->get_next( ).
    WHILE li_element IS BOUND.
      DATA(li_href) = li_element->get_attribute_node( 'href' ).
      IF li_href->get_value( ) CP '##o*'.
        INSERT VALUE #( value     = li_href->get_value( )
                        attribute = li_href ) INTO TABLE lt_hrefs.
      ENDIF.
      li_element ?= li_iterator->get_next( ).
    ENDWHILE.

    li_iterator = ii_document->create_iterator_filtered(
      ii_document->create_filter_and( filter1 = ii_document->create_filter_node_type( if_ixml_node=>co_node_element )
                                      filter2 = ii_document->create_filter_attribute( 'id' ) ) ).
    li_element ?= li_iterator->get_next( ).
    WHILE li_element IS BOUND.
      DATA(lv_old) = li_element->get_attribute( 'id' ).
      IF lv_old CP 'o*'.
        lv_count = lv_count + 1.
        DATA(lv_new) = |o{ lv_count }|.
        li_element->set_attribute( name  = 'id'
                                   value = lv_new ).
        LOOP AT lt_hrefs INTO DATA(ls_href) WHERE value = |#{ lv_old }|.
          ls_href-attribute->set_value( |#{ lv_new }| ).
        ENDLOOP.
      ENDIF.
      li_element ?= li_iterator->get_next( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD clear_cache_info.
    DATA lt_nodes TYPE STANDARD TABLE OF REF TO if_ixml_node WITH EMPTY KEY.

    DATA(li_collection) = ii_document->get_elements_by_tag_name_ns( 'CACHE_INFO' ).
    IF li_collection IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA(li_iterator) = li_collection->create_iterator( ).
    DATA(li_node)     = li_iterator->get_next( ).
    WHILE li_node IS BOUND.
      APPEND li_node TO lt_nodes.
      li_node = li_iterator->get_next( ).
    ENDWHILE.
    LOOP AT lt_nodes INTO li_node.
      li_node->get_parent( )->replace_child( new_child = ii_document->create_element_ns( 'CACHE_INFO' )
                                             old_child = li_node ).
    ENDLOOP.
  ENDMETHOD.

  METHOD prepare_replace.
    rs_info = check_replace( iv_original     = iv_original
                             iv_copy         = iv_copy
                             iv_transport    = iv_transport
                             iv_check_author = iv_check_author ).
  ENDMETHOD.

  METHOD replace.
    DATA(ls_info) = check_replace( iv_original     = iv_original
                                   iv_copy         = iv_copy
                                   iv_transport    = iv_transport
                                   iv_check_author = iv_check_author ).
    IF ls_info-token <> iv_token.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ iv_original } or { iv_copy } changed after prepare (original last changed by | &&
                    |{ ls_info-lastuser }): run prepare again|.
    ENDIF.
    " As for a copy: without ADS a form is not saved
    ads_version( ).

    corr_insert( iv_name      = iv_original
                 iv_devclass  = ls_info-devclass
                 iv_language  = ls_info-language
                 iv_transport = iv_transport ).
    TRY.
        replace_layout( iv_name   = iv_original
                        iv_layout = renew_timestamp( ls_info-copy_layout ) ).
        activate( iv_original ).
        rv_fm_name = function_module( iv_original ).
      CATCH zai_cx_adobe_form INTO DATA(lx_error).
        " The entry in the request stays: say so, otherwise the unchanged version would be released
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |{ lx_error->get_text( ) } (warning: { iv_original } is already recorded in transport request { iv_transport })|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD check_replace.
    " First the checks on names and request, which need no existing forms
    IF iv_original NP 'Z*' AND iv_original NP 'Y*'.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Replacement allowed only for Adobe forms Z* or Y*: { iv_original } refused|.
    ENDIF.
    IF iv_original CP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ iv_original } is a { gc_writable_pattern } copy: specify the original form|.
    ENDIF.
    IF iv_copy NP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |The copy must be an Adobe form { gc_writable_pattern }: { iv_copy } refused|.
    ENDIF.
    rs_info-tr_owner = check_transport( iv_transport ).

    SELECT SINGLE devclass, author, masterlang FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = @gc_object_form
        AND obj_name = @iv_original
      INTO @DATA(ls_tadir).
    IF sy-subrc <> 0 OR ls_tadir-devclass IS INITIAL OR ls_tadir-devclass = '$TMP'.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Adobe form { iv_original } is not in the object directory or is local ($TMP): cannot be replaced|.
    ENDIF.
    " With the logged-on user, not the one declared in the client configuration
    IF iv_check_author = abap_true AND ls_tadir-author <> sy-uname.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Adobe form { iv_original } belongs to another user: author { ls_tadir-author }, logged-on user { sy-uname }|.
    ENDIF.

    " An inactive version means that someone is changing the form in SFP
    SELECT SINGLE @abap_true FROM fplayout
      WHERE name  = @iv_original
        AND state = 'I'
      INTO @DATA(lv_inactive).
    IF lv_inactive = abap_true.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Adobe form { iv_original } has an inactive version: activate it or discard it in SFP first|.
    ENDIF.
    SELECT SINGLE lastuser FROM fplayout
      WHERE name  = @iv_original
        AND state = 'A'
      INTO @DATA(lv_lastuser).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form EXPORTING iv_text = |Adobe form { iv_original } not found or not active|.
    ENDIF.

    " The copy must be one of the kit: local and of the logged-on user
    SELECT SINGLE devclass, author FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = @gc_object_form
        AND obj_name = @iv_copy
      INTO @DATA(ls_copy).
    IF sy-subrc <> 0 OR ls_copy-devclass <> '$TMP' OR ls_copy-author <> sy-uname.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Copy { iv_copy } not found, or not in $TMP of the logged-on user|.
    ENDIF.

    DATA(ls_original_form) = read( iv_original ).
    DATA(ls_copy_form)     = read( iv_copy ).
    check_layout( ls_copy_form-layout ).

    " The token is a snapshot of original (package and author included) and copy: if they change
    " before execute, the replacement is refused
    rs_info-devclass    = ls_tadir-devclass.
    rs_info-author      = ls_tadir-author.
    rs_info-lastuser    = lv_lastuser.
    rs_info-language    = ls_tadir-masterlang.
    rs_info-form        = ls_original_form-form.
    rs_info-layout      = ls_original_form-layout.
    rs_info-copy_layout = ls_copy_form-layout.
    rs_info-token       = cl_http_utility=>encode_base64( |{ ls_tadir-devclass }\|{ ls_tadir-author }\|{ lv_lastuser }\|| &&
                                                          |{ fingerprint( ls_original_form ) }\|{ fingerprint( ls_copy_form ) }| ).
  ENDMETHOD.

  METHOD check_transport.
    SELECT SINGLE trfunction, trstatus, strkorr, as4user FROM e070
      WHERE trkorr = @iv_transport
      INTO @DATA(ls_request).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Transport request { iv_transport } does not exist|.
    ENDIF.
    IF ls_request-strkorr IS NOT INITIAL.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ iv_transport } is a task of request { ls_request-strkorr }: give the request|.
    ENDIF.
    IF ls_request-trfunction <> 'K' OR ( ls_request-trstatus <> 'D' AND ls_request-trstatus <> 'L' ).
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |Transport request { iv_transport } is already released or is not a workbench request|.
    ENDIF.
    rv_owner = ls_request-as4user.
  ENDMETHOD.

  METHOD fingerprint.
    DATA lv_form   TYPE string.
    DATA lv_layout TYPE string.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_raw( EXPORTING if_algorithm  = 'SHA1'
                                                                  if_data       = is_form-form
                                                        IMPORTING ef_hashstring = lv_form ).
        cl_abap_message_digest=>calculate_hash_for_raw( EXPORTING if_algorithm  = 'SHA1'
                                                                  if_data       = is_form-layout
                                                        IMPORTING ef_hashstring = lv_layout ).
      CATCH cx_abap_message_digest INTO DATA(lx_error).
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Fingerprint of the form not computed: { lx_error->get_text( ) }|
            previous = lx_error.
    ENDTRY.
    rv_hash = |{ lv_form }{ lv_layout }|.
  ENDMETHOD.

  METHOD corr_insert.
    " Records the object in the given request without popup, before the form is opened for writing
    CALL FUNCTION 'RS_CORR_INSERT'
      EXPORTING
        object                   = iv_name
        object_class             = gc_object_form
        global_lock              = abap_true
        devclass                 = iv_devclass
        korrnum                  = iv_transport
        use_korrnum_immediatedly = abap_true
        master_language          = iv_language
        suppress_dialog          = abap_true
      EXCEPTIONS
        cancelled                = 1
        permission_failure       = 2
        unknown_objectclass      = 3
        OTHERS                   = 4.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_adobe_form
        EXPORTING
          iv_text = |{ iv_name } not recorded in transport request { iv_transport }: { sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 }|.
    ENDIF.
  ENDMETHOD.

  METHOD replace_layout.
    DATA li_wb_form TYPE REF TO if_fp_wb_form.
    DATA li_form    TYPE REF TO if_fp_form.
    TRY.
        li_wb_form = cl_fp_wb_form=>load( i_name = iv_name
                                          i_mode = if_fp_wb_object=>c_mode_write ).
        li_form ?= li_wb_form->get_object( ).
        li_form->get_layout( )->set_layout_data( iv_layout ).
        li_wb_form->save( ).
        li_wb_form->free( ).
      CATCH cx_fp_api INTO DATA(lx_error).
        " Releases the lock, if the form was opened
        IF li_wb_form IS BOUND.
          TRY.
              li_wb_form->free( ).
            CATCH cx_fp_api ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        RAISE EXCEPTION TYPE zai_cx_adobe_form
          EXPORTING
            iv_text  = |Adobe form { iv_name }: layout not replaced: { lx_error->get_text( ) }|
            previous = lx_error.
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
