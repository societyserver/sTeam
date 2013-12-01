#include <attributes.h>

#define NS_XSI     "http://www.w3.org/2001/XMLSchema-instance"
#define NS_SOAPENC "http://schemas.xmlsoap.org/soap/encoding/"
#define NS_XSE     "http://schemas.xmlsoap.org/soap/envelope/"
#define NS_XSD     "http://www.w3.org/2001/XMLSchema"
#define NS_SOAP    "http://schemas.xmlsoap.org/wsdl/soap/"

#define NAMESPACES(u)  "xmlns:steam=\"urn:"+u+"\"\n"+\
"xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"\n"+\
"xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap/\"\n"+\
"xmlns:soapenc=\"http://schemas.xmlsoap.org/soap/encoding/\"\n"+\
"xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\"\n"+\
"xmlns=\"http://schemas.xmlsoap.org/wsdl/\"\n"

static string xsd_type(string piketype, void|string prefix) 
{
  if ( !stringp(prefix) ) prefix = "steam";
  
  if ( sscanf(piketype, "array(%s)", piketype) )
    return prefix+":Array"+piketype;

  array types = piketype / " | ";
  int i;
  if ( sizeof(types) == 2 && (i=search(types, "object")) >= 0 ) {
    if ( i == 0 )
      piketype = types[1];
    else
      piketype = types[0];
  }

  switch(piketype) {
  case "string":
    return "xsd:string";
  case "int":
    return "xsd:int";
  case "float":
    return "xsd:float";
  }
  return "xsd:anyType";
}

class ServiceFunction {
  void create(function func, void|array params) { 
    serviceFunc = func;
    serviceParams = params;
  }
  function serviceFunc;
  array serviceParams;

  string get_operation() { return function_name(serviceFunc); }
  string get_type() { return sprintf("%O",_typeof(serviceFunc)); }

  array(mapping) get_parts() 
  {
    string         response, paramlist;
    array                       params;
    array                parts = ({ });
    string           type = get_type();
    int                     pcount = 0;
    
    sscanf(type, "function(%s : %s)", paramlist, response);
    params = paramlist / ", ";
    foreach (params, string p) {
      string name;
      if ( !stringp(p) || strlen(p) < 2 )
        continue;
      if (arrayp(serviceParams) && sizeof(serviceParams) > pcount) 
	name = serviceParams[pcount];
      else
	name = "in" + pcount;
	
      parts += ({ ([ "name": name, 
		     "type": xsd_type(p),
		     "typeof": p, ]) });
      pcount++;
    }
    parts += ({ ([ "name": "return",
		"type": xsd_type(response),
		"typeof": response,
    ]) });

    return parts;
  }
}

class WSDL {
  array(function) operations;
  object service;
  string serviceName;
  
  void create(object ws) {
    service = ws;
    serviceName = ws->get_webservice_name();
    operations = ws->get_webservices();
  }

  string render_types() {
    string types = sprintf("<xsd:schema targetNamespace=\"urn:%s\">", 
			   serviceName) ;

    foreach(operations, object op) {
      array opParts = op->get_parts();
      foreach(opParts, mapping part) {
	string type = part->typeof;
	if ( sscanf(type, "array(%s)", type) ) {
	  types += sprintf("<xsd:complexType name=\"%s\">", "Array" + type);
	  types += "<xsd:complexContent>\n";
	  types += "<xsd:restriction base=\"soapenc:Array\">";
	  types += sprintf("<xsd:attribute ref=\"soapenc:arrayType\" wsdl:arrayType=\"%s[]\" />", xsd_type(type));
	  types += "</xsd:restriction>\n</xsd:complexContent>\n</xsd:complexType>\n";
	}
      }
    }
    types += "</xsd:schema>\n";
    return types;
  }

  string render_messages() {
    string messages = "";

    foreach(operations, object op) {
      string opName = op->get_operation();
      array opParts = op->get_parts();
      
      messages += sprintf("<message name=\"%s\">\n", opName);
      foreach(opParts, mapping part) {
	if (part->name != "return")
	  messages += sprintf("<part name=\"%s\" type=\"%s\" />\n", 
			      part->name, part->type);
      }
      messages += "</message>\n";
      messages += sprintf("<message name=\"%sResponse\">\n", opName);
      foreach(opParts, mapping part) {
	if (part->name == "return")
	  messages += sprintf("<part name=\"%s\" type=\"%s\" />\n", 
			      part->name, part->type);
      }
      messages += "</message>\n";
    }
    return messages;
  }

  string render_ports() {
    string ports = sprintf("<portType name=\"%sPort\">\n", serviceName);

    foreach(operations, object op) {
      string opName = op->get_operation();
      ports += sprintf("<operation name=\"%s\">\n", opName);
      ports += sprintf("<input message=\"steam:%s\" name=\"%s\"/>", 
		       opName, opName);
      ports += sprintf("<output message=\"steam:%sResponse\" name=\"%sResponse\"/>",  opName, opName);
      
      ports += "</operation>\n";
    }
    ports += "</portType>\n";
    return ports;
  }

  string render_binding() {
    string binding = sprintf("<binding name=\"%s\" type=\"steam:%s\">\n",
			     serviceName + "Binding", serviceName + "Port");
    
    binding += "<soap:binding style=\"rpc\" transport=\"http://schemas.xmlsoap.org/soap/http\"/>\n";

    foreach(operations, object op) {
      binding += sprintf("<operation name=\"%s\">\n", op->get_operation());
      binding += sprintf("<soap:operation soapAction=\"urn:%s\"/>",
			 serviceName + "Action");
      binding += "<input>\n";
      binding += sprintf("<soap:body use=\"encoded\" namespace=\"urn:%s\" encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"/>\n", serviceName);
      binding += "</input>\n";
      binding += "<output>\n";
      binding += sprintf("<soap:body use=\"encoded\" namespace=\"urn:%s\" encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"/>\n", serviceName);
      binding += "</output>\n";

      binding += "</operation>\n";
    }
    binding += "</binding>\n";

    return binding;
  }

  string render_wsdl() {
    string wsdl = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"+
      sprintf("<definitions name=\"%s\" targetNamespace=\"urn:%s\" %s>\n",
	      serviceName,
	      service->get_webservice_urn(),
	      NAMESPACES(serviceName));
    wsdl += "<types>\n" + render_types() + "</types>\n";
    wsdl += render_messages() + "\n";
    wsdl += render_ports() + "\n";
    wsdl += render_binding() + "\n";
    
    wsdl += sprintf("<service name=\"%s\">\n<port name=\"%s\" binding=\"steam:%s\">\n", serviceName + "Service", serviceName + "Port", serviceName + "Binding");
    wsdl += sprintf("<soap:address location=\"%s\"/>\n</port>\n</service>\n",
		    service->get_address());

    wsdl += "</definitions>\n";
    return wsdl;
  }  
}

class Service {
  object webserviceHandler;

  void create(object ws)
  {
    webserviceHandler = ws;
  }

  string get_address() {
    return _Server->get_server_url_presentation() + webserviceHandler->query_attribute(OBJ_URL)[1..];
  }
  string get_webservice_name() {
    return webserviceHandler->get_webservice_name();
  }

  string get_webservice_urn() {
    return webserviceHandler->get_webservice_urn();
  }

  array get_webservices() {
    return webserviceHandler->get_webservices();
  }
}

SoapEnvelope parse_soap(string xml)
{
  object root = Parser.XML.NSTree.parse_input(xml);

  foreach(root->get_elements(), object n) {
    if ( lower_case(n->get_tag_name()) == "envelope" ) {
      return SoapEnvelope(n);
    }
  }
  return 0;
}

mixed parse_param(object pnode) 
{
    string pname = pnode->get_tag_name();
    mapping attributes = pnode->get_ns_attributes();
    // dont care for order to params right now...
    mapping xsi = attributes[NS_XSI] || ([ ]);
    mapping xse = attributes[NS_SOAPENC] || ([ ]);
    if( xse->arrayType) {
      array result = ({ });
      foreach(pnode->get_elements(), object item) {
	if ( lower_case(item->get_tag_name()) == "item" ) {
	  result += ({ parse_param(item) });
	}
      }
      return result;
    }
    else {
      switch (xsi->type) {
      case "xsd:string": 
	return pnode->value_of_node();
	break;
      case "xsd:int":
	return (int)pnode->value_of_node();
      case "xsd:float":
	return (float)pnode->value_of_node();
      default:
	return (string)pnode->value_of_node();
      }
    }
    return 0;
}



mapping parse_service_call(object obj, object node)
{
  // the function corresponds to the tagname
  string functionName = node->get_tag_name();
  function func = obj[functionName];
  mapping call = ([ "function": func, "params": ({ }), "result":0 ]);
  
  // the parameters
  foreach(node->get_elements(), object p) {
    call->params += ({ parse_param(p) });
  }
  return call;
}


static object xml_result(string prefix, mapping result, object parent)
{
  string resultType = sprintf("%O",_typeof(result->result));
  string resultName = prefix+":return";
  resultType = xsd_type(resultType, prefix);

  string resultxml;
  switch(resultType) {
  case "xsd:string":
    resultxml = (string)result->result;
    break;
  }
  
  object resultNode = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ELEMENT, 
					       resultName,
					       ([ "xsi:type": resultType, ]),
					       "",
					       parent);
  resultNode->add_namespace(NS_XSI, "xsi");
  resultNode->add_namespace(NS_XSD, "xsd");
  werror("Attributes = %O\n", resultNode->get_attributes());
  object textNode = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_TEXT, "",
					     ([ ]), resultxml, resultNode);

  object attrNode = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ATTR, 
					     resultName,
					     ([ "xsi:type": resultType, ]),
					     "",
					     resultNode);
  return resultNode;
}

void add_service_results(SoapEnvelope envelope, 
			 mapping(object:mapping) callResults) 
{
    object bodyNode = envelope->get_body()->get_node();

    // callresult is a mapping of XML Nodes that represent the call to 
    // results of the call as in parse_service_call
    int namespace_count = 1;
    foreach(indices(callResults), object callNode) {
      string ns = callNode->get_ns();
      string prefix = "ns" + namespace_count;

      // register a namespace per call (ns1... nsn)
      envelope->add_namespace(ns, prefix);
      namespace_count++;
      mapping attributes = callNode->get_attributes();
      attributes["xmlns:"+prefix] = ns;

      // clone does not work....
      object myCall = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ELEMENT,
					       callNode->get_xml_name()+
					       "Response",
					       attributes,
					       "",
					       bodyNode);

      xml_result(prefix, callResults[callNode], myCall);
    }
}

class SoapHeader {
  array headerElements;
  void create(void|object node) {
    if ( objectp(node) )
      headerElements = node->get_elements();
    else 
      headerElements = ({ });
  }
}

class SoapBody {
  array bodyElements;
  object bodyNode;

  void create(void|object node) {
    if ( objectp(node) ) {
      bodyNode = node;
      bodyElements = node->get_elements();
    }
    else
      bodyElements = ({ });
  }
  
  array get_elements() { return bodyElements; }

  array lookup_elements(string ns) {
    array result = ({ });

    foreach(bodyElements, object element) {
      werror("Lookup Element: %s, check %s %s\n",
	     ns, element->get_ns(), element->get_tag_name());
      if ( element->get_ns() == ns )
	result += ({ element });
    }
    return result;
  }

  object lookup_element(string name, string ns) {
    foreach(bodyElements, object element) {
      werror("Lookup Element: %s %s, check %s %s\n",
	     ns, name, element->get_ns(), element->get_tag_name());
      if ( element->get_ns() == ns && element->get_tag_name() == name )
	return element;
    }
  }

  object get_node() { return bodyNode; }
}


class SoapEnvelope {
  SoapHeader header;
  SoapBody     body;
  object    xmlNode;

  void set_xml(object node) {
    foreach(node->get_elements(), object n) {
      if ( lower_case(n->get_tag_name()) == "header" ) {
	header = SoapHeader(n);
      }
      if ( lower_case(n->get_tag_name()) == "body" ) {
	body = SoapBody(n);
      }
    }
    xmlNode = node;
  }

  void create(void|object node) {
    if ( objectp(node) ) {
      set_xml(node);
    } else {
      xmlNode = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ROOT, 
					 "soapmessage", ([ ]), "");
      xmlNode = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ELEMENT, 
					 "soapenv:Envelope",
					 ([ "xmlns:soap": NS_SOAP,
					    "xmlns:xsi": NS_XSI,
					    "xmlns:soapenc": NS_SOAPENC,
					    "xmlns:soapenv": NS_XSE,
					    "xmlns:xsd": NS_XSD, 
					 ]), "", xmlNode);
      xmlNode->add_namespace(NS_XSI, "xsi");
      xmlNode->add_namespace(NS_XSE, "soapenv");
      xmlNode->add_namespace(NS_SOAP,"soap");
      xmlNode->add_namespace(NS_SOAPENC, "soapenc");
      xmlNode->add_namespace(NS_XSD, "xsd");
      object node = Parser.XML.NSTree.NSNode(Parser.XML.Tree.XML_ELEMENT,
				      "soapenv:Body", ([ ]), "", xmlNode);
      
      header = SoapHeader();
      body = SoapBody(node);
    }
  }

  void add_namespace(string ns, string prefix) 
  {
    xmlNode->add_namespace(ns, prefix);
  }

  string render() {

    return "<?xml version='1.0' encoding='utf-8'?>\n"+xmlNode->render_xml();
  }
  
  object get_node() { return xmlNode; }
  SoapBody get_body() { return body; }

  array get_body_elements() { return body->get_elements(); }

  array lookup_body_elements(string ns) { return body->lookup_elements(ns); }

  object lookup_body_element(string name, string ns) {
    return body->lookup_element(name, ns);
  }
}
