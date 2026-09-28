"! Reads and writes SmartForms as XML (same format as download/upload in transaction
"! SMARTFORMS). Free writing is limited to local ZAI_* forms ($TMP) of the current user;
"! replacing a customer form Z*/Y* goes through prepare_replace/replace, with a transport
"! request and a version token. Nothing is ever deleted.
CLASS zai_cl_smartform_xml DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_write_result,
             fm_name TYPE rs38l_fnam,
             created TYPE abap_bool,
           END OF ty_write_result.

    TYPES: BEGIN OF ty_replace_info,
             devclass TYPE devclass,
             author   TYPE responsibl,
             lastuser TYPE syuname,
             lastdate TYPE sydatum,
             lasttime TYPE syuzeit,
             language TYPE sylangu,
             tr_owner TYPE as4user,
             token    TYPE string,
             xml      TYPE xstring,
           END OF ty_replace_info.

    "! Name pattern of writable forms
    CONSTANTS gc_writable_pattern TYPE string VALUE `ZAI_*`.

    METHODS read
      IMPORTING iv_name       TYPE tdsfname
      RETURNING VALUE(rv_xml) TYPE xstring
      RAISING   zai_cx_smartform.

    METHODS write
      IMPORTING iv_name          TYPE tdsfname
                iv_xml           TYPE xstring
      RETURNING VALUE(rs_result) TYPE ty_write_result
      RAISING   zai_cx_smartform.

    "! Checks and data to replace a customer form with a ZAI_* copy; no writes
    METHODS prepare_replace
      IMPORTING iv_original     TYPE tdsfname
                iv_copy         TYPE tdsfname
                iv_transport    TYPE trkorr
                iv_check_author TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rs_info)  TYPE ty_replace_info
      RAISING   zai_cx_smartform.

    "! Replaces the original with the copy and records it in the request; the token must come from prepare_replace
    METHODS replace
      IMPORTING iv_original       TYPE tdsfname
                iv_copy           TYPE tdsfname
                iv_transport      TYPE trkorr
                iv_token          TYPE string
                iv_check_author   TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv_fm_name) TYPE rs38l_fnam
      RAISING   zai_cx_smartform.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_target,
             form_exists  TYPE abap_bool,
             tadir_exists TYPE abap_bool,
             language     TYPE sylangu,
           END OF ty_target.

    METHODS check_target
      IMPORTING iv_name          TYPE tdsfname
      RETURNING VALUE(rs_target) TYPE ty_target
      RAISING   zai_cx_smartform.

    METHODS parse
      IMPORTING iv_xml         TYPE xstring
      RETURNING VALUE(ri_root) TYPE REF TO if_ixml_element
      RAISING   zai_cx_smartform.

    METHODS xml_language
      IMPORTING ii_root            TYPE REF TO if_ixml_element
      RETURNING VALUE(rv_language) TYPE sylangu.

    METHODS tadir_entry
      IMPORTING iv_name   TYPE tdsfname
                iv_delete TYPE abap_bool DEFAULT abap_false
      RAISING   zai_cx_smartform.

    METHODS upload_and_store
      IMPORTING iv_name     TYPE tdsfname
                ii_root     TYPE REF TO if_ixml_element
                iv_language TYPE sylangu
                iv_exists   TYPE abap_bool
                iv_devclass TYPE devclass DEFAULT '$TMP'
      RAISING   zai_cx_smartform.

    METHODS check_replace
      IMPORTING iv_original     TYPE tdsfname
                iv_copy         TYPE tdsfname
                iv_transport    TYPE trkorr
                iv_check_author TYPE abap_bool
      RETURNING VALUE(rs_info)  TYPE ty_replace_info
      RAISING   zai_cx_smartform.

    METHODS corr_insert
      IMPORTING iv_name      TYPE tdsfname
                iv_devclass  TYPE devclass
                iv_language  TYPE sylangu
                iv_transport TYPE trkorr
      RAISING   zai_cx_smartform.

    METHODS check_form
      IMPORTING io_form TYPE REF TO cl_ssf_fb_smart_form
      RAISING   zai_cx_smartform.

    METHODS generate
      IMPORTING iv_name           TYPE tdsfname
      RETURNING VALUE(rv_fm_name) TYPE rs38l_fnam
      RAISING   zai_cx_smartform.
ENDCLASS.


CLASS zai_cl_smartform_xml IMPLEMENTATION.
  METHOD read.
    " Original language: the form texts are stored in that language
    SELECT SINGLE masterlang FROM stxfadm
      WHERE formname = @iv_name
      INTO @DATA(lv_language).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform EXPORTING iv_text = |SmartForms { iv_name } not found|.
    ENDIF.

    DATA(lo_form) = NEW cl_ssf_fb_smart_form( ).
    TRY.
        lo_form->load( im_formname = iv_name
                       im_language = lv_language ).
      CATCH cx_ssf_fb INTO DATA(lx_load).
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text  = |SmartForms { iv_name } cannot be read: { lx_load->get_text( ) }|
            previous = lx_load.
    ENDTRY.

    DATA(li_ixml)     = cl_ixml=>create( ).
    DATA(li_document) = li_ixml->create_document( ).
    lo_form->xml_init( ).
    lo_form->xml_download( EXPORTING parent   = li_document
                           CHANGING  document = li_document ).

    " Namespace and language declarations as in the download of transaction SMARTFORMS:
    " XML_UPLOAD recognizes the nodes by their namespace only
    DATA(li_root) = li_document->get_root_element( ).
    li_root->set_attribute( name      = 'sf'
                            namespace = 'xmlns'
                            value     = cl_ssf_fb_sf_basis=>xml_ns_uri_sf ).
    li_root->set_attribute( name  = 'xmlns'
                            value = cl_ssf_fb_sf_basis=>xml_ns_uri_ifr ).
    DATA lv_iso TYPE laiso.
    CALL FUNCTION 'CONVERSION_EXIT_ISOLA_OUTPUT'
      EXPORTING
        input  = lv_language
      IMPORTING
        output = lv_iso.
    li_root->set_attribute( name      = 'language'
                            namespace = 'sf'
                            value     = CONV string( lv_iso ) ).

    " One line per element: the file stays editable line by line
    DATA(li_stream) = li_ixml->create_stream_factory( )->create_ostream_xstring( string = rv_xml ).
    li_stream->set_pretty_print( abap_true ).
    li_ixml->create_renderer( ostream  = li_stream
                              document = li_document )->render( ).
  ENDMETHOD.

  METHOD write.
    " Checks before any lock or write
    DATA(ls_target) = check_target( iv_name ).
    DATA(li_root)   = parse( iv_xml ).
    " New form: original language taken from the XML, so the texts stay in their language
    DATA(lv_language) = COND sylangu( WHEN ls_target-form_exists = abap_true
                                      THEN ls_target-language
                                      ELSE xml_language( li_root ) ).

    IF ls_target-tadir_exists = abap_false.
      tadir_entry( iv_name ).
    ENDIF.

    TRY.
        upload_and_store( iv_name     = iv_name
                          ii_root     = li_root
                          iv_language = lv_language
                          iv_exists   = ls_target-form_exists ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        " All or nothing: the TADIR entry created here must not be left orphaned
        IF ls_target-tadir_exists = abap_false.
          TRY.
              tadir_entry( iv_name   = iv_name
                           iv_delete = abap_true ).
            CATCH zai_cx_smartform ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        RAISE EXCEPTION lx_error.
    ENDTRY.

    rs_result = VALUE #( fm_name = generate( iv_name )
                         created = xsdbool( ls_target-form_exists = abap_false ) ).
  ENDMETHOD.

  METHOD check_target.
    IF iv_name NP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Writing allowed only for SmartForms { gc_writable_pattern }: { iv_name } refused|.
    ENDIF.

    SELECT SINGLE devclass, author FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'SSFO'
        AND obj_name = @iv_name
      INTO @DATA(ls_tadir).
    IF sy-subrc = 0.
      IF ls_tadir-devclass <> '$TMP' OR ls_tadir-author <> sy-uname.
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text = |SmartForms { iv_name } cannot be changed: package { ls_tadir-devclass }, author { ls_tadir-author }|.
      ENDIF.
      rs_target-tadir_exists = abap_true.
    ENDIF.

    SELECT SINGLE masterlang FROM stxfadm
      WHERE formname = @iv_name
      INTO @rs_target-language.
    rs_target-form_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD parse.
    DATA lt_indentation TYPE STANDARD TABLE OF REF TO if_ixml_node WITH EMPTY KEY.

    DATA(li_ixml)     = cl_ixml=>create( ).
    DATA(li_factory)  = li_ixml->create_stream_factory( ).
    DATA(li_document) = li_ixml->create_document( ).
    DATA(li_parser)   = li_ixml->create_parser( stream_factory = li_factory
                                                istream        = li_factory->create_istream_xstring( iv_xml )
                                                document       = li_document ).
    " Normalizing would strip the leading spaces of code and texts
    li_parser->set_normalizing( abap_false ).
    IF li_parser->parse( ) <> 0.
      DATA(li_parse_error) = li_parser->get_error( index = 0 ).
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Invalid XML: { COND #( WHEN li_parse_error IS BOUND THEN li_parse_error->get_reason( ) ) }|.
    ENDIF.

    " Remove only the indentation between elements: XML_UPLOAD reads the first child as an element in several places
    DATA(li_iterator) = li_document->create_iterator( ).
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

    ri_root = li_document->get_root_element( ).
    IF ri_root IS INITIAL OR ri_root->get_name( ) <> 'SMARTFORM'.
      RAISE EXCEPTION TYPE zai_cx_smartform EXPORTING iv_text = |Invalid XML: SMARTFORM root missing|.
    ENDIF.
    " Without namespace XML_UPLOAD ignores all nodes and would save an empty form
    IF ri_root->get_namespace_uri( ) <> cl_ssf_fb_sf_basis=>xml_ns_uri_sf.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Invalid XML: SmartForms namespace { cl_ssf_fb_sf_basis=>xml_ns_uri_sf } missing on the root|.
    ENDIF.
    " Same risk with a form without content: neither XML_UPLOAD nor CHECK rejects it
    IF ri_root->find_from_name_ns( name  = 'HEADER'
                                   depth = 1
                                   uri   = cl_ssf_fb_sf_basis=>xml_ns_uri_ifr ) IS NOT BOUND.
      RAISE EXCEPTION TYPE zai_cx_smartform EXPORTING iv_text = |Invalid XML: form HEADER missing|.
    ENDIF.
  ENDMETHOD.

  METHOD xml_language.
    " Same attribute read by CL_SSF_FB_SMART_FORM->XML_UPLOAD (ISO language, prefix sf)
    DATA(lv_iso) = ii_root->get_attribute( name      = 'language'
                                           namespace = 'sf' ).
    CALL FUNCTION 'CONVERSION_EXIT_ISOLA_INPUT'
      EXPORTING
        input            = lv_iso
      IMPORTING
        output           = rv_language
      EXCEPTIONS
        unknown_language = 1
        OTHERS           = 2.
    IF sy-subrc <> 0 OR rv_language IS INITIAL.
      rv_language = sy-langu.
    ENDIF.
  ENDMETHOD.

  METHOD tadir_entry.
    " Object directory entry in $TMP created before the lock: this way ENQUEUE and STORE
    " find the local package and do not ask for a transport request
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus         = space
        wi_delete_tadir_entry = iv_delete
        wi_tadir_pgmid        = 'R3TR'
        wi_tadir_object       = 'SSFO'
        wi_tadir_obj_name     = CONV sobj_name( iv_name )
        wi_tadir_devclass     = COND devclass( WHEN iv_delete = abap_false THEN '$TMP' )
      EXCEPTIONS
        OTHERS                = 1.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |TADIR entry for { iv_name } not { COND #( WHEN iv_delete = abap_true THEN `removed` ELSE `created` ) }: | &&
                    |{ sy-msgid } { sy-msgno } { sy-msgv1 }|.
    ENDIF.
  ENDMETHOD.

  METHOD upload_and_store.
    DATA lo_result TYPE REF TO cl_ssf_fb_smart_form.
    DATA(lo_form) = NEW cl_ssf_fb_smart_form( ).

    TRY.
        lo_form->enqueue( suppress_corr_check = abap_true
                          master_language     = iv_language
                          mode                = COND #( WHEN iv_exists = abap_true THEN `MODIFY` ELSE `INSERT` )
                          formname            = iv_name ).
      CATCH cx_ssf_fb INTO DATA(lx_enqueue).
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text  = |SmartForms { iv_name } cannot be locked (edited by another user?): { lx_enqueue->get_text( ) }|
            previous = lx_enqueue.
    ENDTRY.

    TRY.
        lo_form->xml_upload( EXPORTING dom      = ii_root
                                       formname = iv_name
                                       language = iv_language
                             CHANGING  sform    = lo_result ).
        check_form( lo_result ).

        " Administrative data of the target form, not those of the file (as transaction SMARTFORMS does);
        " SSF_SAVE_FORM writes package, version and creation data only on the first save
        CLEAR: lo_result->header-version, lo_result->header-firstuser,
               lo_result->header-firstdate, lo_result->header-firsttime.
        SELECT SINGLE version, firstuser, firstdate, firsttime FROM stxfadm
          WHERE formname = @iv_name
          INTO CORRESPONDING FIELDS OF @lo_result->header.
        IF lo_result->header-firstuser IS INITIAL.
          lo_result->header-version   = 1.
          lo_result->header-firstuser = sy-uname.
          lo_result->header-firstdate = sy-datum.
          lo_result->header-firsttime = sy-uzeit.
        ENDIF.
        lo_result->header-devclass = iv_devclass.
        lo_result->header-lastuser = sy-uname.
        lo_result->header-lastdate = sy-datum.
        lo_result->header-lasttime = sy-uzeit.

        lo_result->store( im_formname = iv_name
                          im_language = iv_language
                          im_active   = abap_true ).
      CATCH cx_ssf_fb INTO DATA(lx_error).
        TRY.
            lo_form->dequeue( iv_name ).
          CATCH cx_ssf_fb ##NO_HANDLER.
        ENDTRY.
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text  = |SmartForms { iv_name } not saved: { lx_error->get_text( ) }|
            previous = lx_error.
      CATCH zai_cx_smartform INTO DATA(lx_check).
        TRY.
            lo_form->dequeue( iv_name ).
          CATCH cx_ssf_fb ##NO_HANDLER.
        ENDTRY.
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text  = |SmartForms { iv_name } not saved: { lx_check->get_text( ) }|
            previous = lx_check.
    ENDTRY.

    TRY.
        lo_form->dequeue( iv_name ).
      CATCH cx_ssf_fb ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD check_form.
    " As in transaction SMARTFORMS: warnings do not block, only messages of class error do
    TRY.
        io_form->check( global_check_flag = abap_true ).
      CATCH cx_ssf_fb_check INTO DATA(lx_check).
        DATA(lt_errors) = VALUE string_table( FOR ls_error IN lx_check->error_table
                                              WHERE ( class = cl_ssf_fb_check=>c_error )
                                              ( condense( CONV string( ls_error-msg ) ) ) ).
        IF lt_errors IS NOT INITIAL.
          RAISE EXCEPTION TYPE zai_cx_smartform
            EXPORTING
              iv_text  = |Form check: { lines( lt_errors ) } errors, e.g. { concat_lines_of( table = VALUE string_table( FOR lv_error IN lt_errors FROM 1 TO 3 ( lv_error ) ) sep = ` / ` ) }|
              previous = lx_check.
        ENDIF.
    ENDTRY.
  ENDMETHOD.

  METHOD generate.
    CALL FUNCTION 'FB_GENERATE_FORM'
      EXPORTING
        i_formname       = iv_name
      EXCEPTIONS
        no_name          = 1
        no_form          = 2
        no_active_source = 3
        generation_error = 4
        illegal_formtype = 5
        OTHERS           = 6.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |SmartForms { iv_name } saved but not generated (return code { sy-subrc }): { sy-msgid } { sy-msgno } { sy-msgv1 }|.
    ENDIF.

    CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
      EXPORTING
        formname           = iv_name
      IMPORTING
        fm_name            = rv_fm_name
      EXCEPTIONS
        no_form            = 1
        no_function_module = 2
        OTHERS             = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |SmartForms { iv_name } saved but function module not available (return code { sy-subrc })|.
    ENDIF.
  ENDMETHOD.

  METHOD prepare_replace.
    rs_info = check_replace( iv_original     = iv_original
                             iv_copy         = iv_copy
                             iv_transport    = iv_transport
                             iv_check_author = iv_check_author ).
    rs_info-xml = read( iv_original ).
  ENDMETHOD.

  METHOD replace.
    DATA(ls_info) = check_replace( iv_original     = iv_original
                                   iv_copy         = iv_copy
                                   iv_transport    = iv_transport
                                   iv_check_author = iv_check_author ).
    IF ls_info-token <> iv_token.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |{ iv_original } or { iv_copy } changed after prepare (original last changed by | &&
                    |{ ls_info-lastuser } on { ls_info-lastdate DATE = USER } at { ls_info-lasttime TIME = USER }): run prepare again|.
    ENDIF.

    DATA(li_root) = parse( read( iv_copy ) ).
    corr_insert( iv_name      = iv_original
                 iv_devclass  = ls_info-devclass
                 iv_language  = ls_info-language
                 iv_transport = iv_transport ).
    TRY.
        upload_and_store( iv_name     = iv_original
                          ii_root     = li_root
                          iv_language = ls_info-language
                          iv_exists   = abap_true
                          iv_devclass = ls_info-devclass ).
        rv_fm_name = generate( iv_original ).
      CATCH zai_cx_smartform INTO DATA(lx_error).
        " The entry in the request stays: say so, otherwise the unchanged version would be released
        RAISE EXCEPTION TYPE zai_cx_smartform
          EXPORTING
            iv_text  = |{ lx_error->get_text( ) } (warning: { iv_original } is already recorded in transport request { iv_transport })|
            previous = lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD check_replace.
    " First the checks on names and request, which need no existing forms
    IF iv_original NP 'Z*' AND iv_original NP 'Y*'.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Replacement allowed only for SmartForms Z* or Y*: { iv_original } refused|.
    ENDIF.
    IF iv_original CP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |{ iv_original } is a { gc_writable_pattern } copy: specify the original form|.
    ENDIF.
    IF iv_copy NP gc_writable_pattern.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |The copy must be a SmartForms { gc_writable_pattern }: { iv_copy } refused|.
    ENDIF.

    SELECT SINGLE as4user FROM e070
      WHERE trkorr     = @iv_transport
        AND trfunction = 'K'
        AND trstatus   IN ('D','L')
      INTO @DATA(lv_tr_owner).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Transport request { iv_transport } does not exist, is already released or is not a workbench request|.
    ENDIF.

    SELECT SINGLE devclass, author FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'SSFO'
        AND obj_name = @iv_original
      INTO @DATA(ls_tadir).
    IF sy-subrc <> 0 OR ls_tadir-devclass IS INITIAL OR ls_tadir-devclass = '$TMP'.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |SmartForms { iv_original } is not in the object directory or is local ($TMP): cannot be replaced|.
    ENDIF.
    " With the logged-on user, not the one declared in the client configuration
    IF iv_check_author = abap_true AND ls_tadir-author <> sy-uname.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |SmartForms { iv_original } belongs to another user: author { ls_tadir-author }, logged-on user { sy-uname }|.
    ENDIF.

    SELECT SINGLE version, lastuser, lastdate, lasttime, masterlang FROM stxfadm
      WHERE formname = @iv_original
      INTO @DATA(ls_original).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform EXPORTING iv_text = |SmartForms { iv_original } not found|.
    ENDIF.
    SELECT SINGLE version, lastdate, lasttime, masterlang FROM stxfadm
      WHERE formname = @iv_copy
      INTO @DATA(ls_copy).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zai_cx_smartform EXPORTING iv_text = |Copy { iv_copy } not found|.
    ENDIF.
    " The copy texts are in its original language: uploaded into the original they would end up in the wrong language
    IF ls_copy-masterlang <> ls_original-masterlang.
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |Different original language: { iv_copy } { ls_copy-masterlang }, { iv_original } { ls_original-masterlang }|.
    ENDIF.

    " The token is a snapshot of the original (package and author included) and of the copy: if they change
    " before execute, the replacement is refused
    rs_info = VALUE #( devclass = ls_tadir-devclass
                       author   = ls_tadir-author
                       lastuser = ls_original-lastuser
                       lastdate = ls_original-lastdate
                       lasttime = ls_original-lasttime
                       language = ls_original-masterlang
                       tr_owner = lv_tr_owner
                       token    = cl_http_utility=>encode_base64(
                                    |{ ls_tadir-devclass }\|{ ls_tadir-author }\|| &&
                                    |{ ls_original-version }\|{ ls_original-lastdate }\|{ ls_original-lasttime }\|| &&
                                    |{ ls_copy-version }\|{ ls_copy-lastdate }\|{ ls_copy-lasttime }| ) ).
  ENDMETHOD.

  METHOD corr_insert.
    " Records the object in the given request without popup: the internal check of ENQUEUE would open one via RFC
    CALL FUNCTION 'RS_CORR_INSERT'
      EXPORTING
        object                   = iv_name
        object_class             = 'SSFO'
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
      RAISE EXCEPTION TYPE zai_cx_smartform
        EXPORTING
          iv_text = |{ iv_name } not recorded in transport request { iv_transport }: { sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 }|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
