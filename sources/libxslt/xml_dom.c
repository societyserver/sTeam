#include <string.h>
#include <stdarg.h>
#include <libxml/xmlmemory.h>
#include <libxml/debugXML.h>
#include <libxml/HTMLtree.h>
#include <libxml/xmlIO.h>
#include <libxml/DOCBparser.h>
#include <libxml/xinclude.h>
#include <libxml/catalog.h>
#include <libxml/xmlversion.h>
#include <libxslt/xslt.h>
#include <libxslt/xsltInternals.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <libxslt/xsltconfig.h>

#include "global.h"
#include "interpret.h"
#include "stralloc.h"
#include "pike_macros.h"
#include "module_support.h"
#include "mapping.h"
#include "threads.h"

#include "xslt.h"


#define safe_push_text(_txt_) if ((_txt_)) push_text((_txt_)); else push_int(0)

static void init_dom(struct object * o);
static void exit_dom(struct object * o);

static void init_node(struct object * o);
static void exit_node(struct object * o);



void f_create_dom(INT32 args)
{
    xmlDocPtr doc;
    xmlNodePtr node;
    struct pike_string *rootStr = NULL;

    if ( args != 1 )
	Pike_error("Wrong number of arguments for creation !");
    else if ( ARG(1).type != T_STRING )
	Pike_error("Incorrect type for argument 1: expected a string !");
    rootStr = ARG(1).u.string;

    doc = xmlNewDoc("1.0");
    THISDOM->domDoc = doc;

    if(doc == NULL)
    {
	Pike_error("Unable to create new XML document.\n");
    }  
    node = xmlNewNode(NULL, (xmlChar *)rootStr->str);
    xmlDocSetRootElement(doc, node);
    THISDOM->rootNode = node;
    if(node == NULL)
    {
	xmlFreeDoc(doc);
	Pike_error("Unable to find Root Node.\n");
    }
    pop_n_elems(args);
}

void f_get_root(INT32 args)
{
    struct object *o;
    xmlNodePtr node = THISDOM->rootNode;
    push_text(node->name);
    o = NEW_NODE();
    OBJ2_NODE(o)->node = node;
    push_object(o);
}

void f_create_node(INT32 args)
{
    struct mapping *attributes = NULL;
    struct pike_string *name = NULL;
    xmlNodePtr                 node;
    struct keypair               *k;

    switch(args) {
    case 2:
	if ( ARG(2).type != T_MAPPING )
	    Pike_error("second argument is attribute mapping of node !");
	attributes = ARG(2).u.mapping;
    case 1:
	break;
    default:
	Pike_error("invalid number of arguments to create node !");
    }
    if ( ARG(1).type != T_STRING )
	Pike_error("first argument needs to be name of the node !");
    name = ARG(1).u.string;

    
    node = xmlNewNode(NULL, (xmlChar *)name->str);
    THISNODE->node = node;

    if ( attributes != NULL ) {
	struct svalue sind, sval;
	int count;
	
	MY_MAPPING_LOOP(attributes, count, k) 
        {
	    sind = k->ind;
	    sval = k->val;
	    if(!(sind.type == T_STRING && sval.type == T_STRING)) {
		continue;
	    }
	    xmlNewProp(node, sind.u.string->str, sval.u.string->str);
	}
    }


    pop_n_elems(args);
}

void f_add_prop(INT32 args)
{
    xmlNodePtr node, current;
    
    if ( args != 2 ) 
      Pike_error("add_prop: invalid number of arguments : expected key/value");
    if ( ARG(1).type != T_STRING || ARG(2).type != T_STRING )
	Pike_error("Incorrect type for arguments: expected string, string !");
    current = THISNODE->node;
    
    xmlNewProp(current, ARG(1).u.string->str, ARG(2).u.string->str);
    pop_n_elems(args);
    push_int(1);
}


void f_add_data(INT32 args)
{
    xmlNodePtr node;
    if ( args != 1 )
	Pike_error("invalid number of arguments to add_data: expected string");
    if ( ARG(1).type != T_STRING )
	Pike_error("Incorrect type for argument 1: expected string");
    node = xmlNewText(ARG(1).u.string->str);
    xmlAddChild(THISNODE->node, node);
    pop_n_elems(args);
    push_int(1);
}

void f_add_child(INT32 args)
{
    xmlNodePtr current;
    
    if ( args != 1 ) 
      Pike_error("invalid number of arguments for add_child: expected object");
    if ( ARG(1).type != T_OBJECT )
	Pike_error("Incorrect type for argument 1: expected an object !");
    struct object* node = ARG(1).u.object;
    current = THISNODE->node;
    
    xmlAddChild(current, OBJ2_NODE(node)->node);
    pop_n_elems(args);
    push_int(1);
}

void f_render_xml(INT32 args)
{
    int dumped;
    xmlBufferPtr buf;
    char * str;

    buf = xmlBufferCreate();
    dumped = xmlNodeDump(buf, THISDOM->domDoc, THISDOM->rootNode, 1, 1);
    pop_n_elems(args);

    if(dumped>0)
    {
	str = (char *)xmlStrdup(buf->content);
	push_text(str);
	xmlBufferFree(buf);
    }
    else
	push_text("");
}

int _init_xml_dom(void)
{
    start_new_program();
    ADD_STORAGE(dom_storage);

    set_init_callback(init_dom);
    set_exit_callback(exit_dom);
    
    ADD_FUNCTION("create", f_create_dom, tFunc(tString, tVoid), 0);
    ADD_FUNCTION("render_xml", f_render_xml, tFunc(tVoid, tString), 0);
    ADD_FUNCTION("get_root", f_get_root, tFunc(tVoid, tObj), 0);
    dom_program = end_program();
    
    add_program_constant("DOM", dom_program, 0);

    start_new_program();
    ADD_STORAGE(node_storage);

    set_init_callback(init_node);
    set_exit_callback(exit_node);
    ADD_FUNCTION("create", f_create_node, tFunc(tString tOr(tMapping, tVoid), tVoid), 0);
    ADD_FUNCTION("add_data", f_add_data, tFunc(tString, tInt), 0);
    ADD_FUNCTION("add_prop", f_add_prop, tFunc(tString tString, tInt), 0);
    ADD_FUNCTION("add_child", f_add_child, tFunc(tObj, tInt), 0);
    node_program = end_program();
    add_program_constant("Node", node_program, 0);
}

int _shutdown_xml_dom(void)
{
  return 1;
}

static void init_dom(struct object *o)
{
  if (!THIS)
    return;

  THISDOM->domDoc = NULL;
  THISDOM->rootNode = NULL;
}

static void init_node(struct object *o)
{
  if (!THISNODE)
    return;

  THISNODE->node = NULL;
}

static void exit_dom(struct object *o)
{
  if (!THIS)
    return;

}

static void exit_node(struct object *o)
{
  if (!THIS)
    return;

}
