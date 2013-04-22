class Node {
    Node          father;
    Node            root;
    string          name;
    string       tagname; // name without NS
    string     ns_prefix;
    string          data;
    mapping   attributes;
    mapping   namespaces;
    string    ns_current;
    array(Node)  children;
    
    void create(string tag, mapping attr, void|object root_node, void|object father_node) 
    {
	name = tag;
	if ( sscanf(name, "%s:%s", ns_prefix, tagname) != 2 )
	    tagname = name;
	if ( mappingp(attr) )
	  attributes = attr;
	else
	  attributes = ([ ]);
	namespaces = ([ ]);
	foreach ( indices(attributes), string attr) {
	    string nsprefix;
	    if ( attr == "xmlns" ) {
		ns_current = attributes[attr]; 
	    }
	    if ( sscanf(attr, "xmlns:%s", nsprefix) == 1 ) {
		namespaces[nsprefix] = attributes[attr];
	    }
	}
	father = father_node;
	root = root_node;
	children = ({ });
	data = "";
	if ( objectp(father) )
	    father->add_child(this_object());
    }
    mapping get_namespaces() { return namespaces; }
    string ns_get_current() {
	return ns_current;
    }
    string ns_lookup(void|string prefix) {
	if ( !stringp(prefix) ) {
	    prefix = ns_prefix;
	    if ( stringp(ns_current) )
		return ns_current;
	}
	if ( namespaces[prefix] )
	    return namespaces[prefix];
	
	if ( objectp(father) )
	    return father->ns_lookup(prefix);
	return 0;
    }
    string get_ns_prefix() {
	return ns_prefix;
    }
    string get_ns() {
	return ns_lookup();
    }
    mapping get_pi() { return root->get_pi(); }

    void add_child(Node child) {
	child->set_parent(this_object());
	children += ({ child });
    }
    void add_children(array childs) {
      foreach(childs, object child)
	child->set_parent(this_object());
      children += childs;
    }
    void replace_children(array childs) {
	children = childs;
	foreach(children, object child)
	  child->set_parent(this_object());
    }
    void replace_child(Node child, array(Node) childs) {
      array new_childs = ({ });
      foreach(children, object s) {
	  if ( s == child && s->get_data() == child->get_data() )
	      new_childs += childs;
	else
	  new_childs += ({ s });
      }
      children = new_childs;
      foreach(children, object child)
	child->set_parent(this_object());
    }
    void set_parent(object f) { father = f; }
    Node get_first_child() {
      if ( sizeof(children) == 0 )
	return 0;
      return children[0];
    }
    Node get_last_child() {
      if ( sizeof(children) == 0 )
	return 0;
      return children[sizeof(children)-1];
    }
    array(Node) get_leafs() {
      array nodes = ({ });
      foreach( children, object child ) {
	if ( !objectp(children->get_first_child()) )
	  nodes += ({ child });
	else
	  nodes += child->get_leafs();
      }
      return nodes;
    }
    Node get_root() {
      if ( objectp(father) )
	return father->get_root();
      return this_object();
    }

    string get_data() { return data; }
    string get_text() { return data; }
    string value_of_node() { return data; }
    string get_name() { return name; }
    string get_tag_name() { 
	return tagname; 
    }
    array(Node) get_children() { return children; }
    Node get_parent() { return father; }

    void set_data(string str) { data = str; }
    void add_data(string str) { data += str; }

    // xpath
    array(Node) get_nodes(string element) {
        if ( element[0] == '/' )
	  return root->get_nodes(element[1..]);
	array(Node) nodes = ({ });
	string rest_xpath;

	sscanf(element, "%s/%s", element, rest_xpath);
	array matches = match_children(element);
	
	foreach(matches, object child) {
	  if ( stringp(rest_xpath) && strlen(rest_xpath) > 0 )
	    nodes += child->get_nodes(rest_xpath);
	  else
	    nodes += ({ child });
	}
	return nodes;
    }
    
    Node get_node(string xpath) {
	string      element;

	if ( !stringp(xpath) || strlen(xpath) == 0 )
	    return this_object();

	if ( xpath[0] == '/' ) 
	  return get_root()->get_node(xpath[1..]);

	if ( sscanf(xpath, "%s/%s", element, xpath) != 2 ) {
	    element = xpath;
	    xpath = "";
	}


	array nodes = match_children(element);

	foreach(nodes, object child) {
	  object res = child->get_node(xpath);
	  // only one path must match!
	  if ( objectp(res) )
	    return res;
	}
	return 0;
    }

    static array(Node) match_children(string single_xpath) {
      string element, constrain, attr, val;
      int req_num = -1;
      if ( !sscanf(single_xpath, "%s[%s]", element, constrain) )
	element = single_xpath;
      else {
	sscanf(constrain, "%d", req_num);
	sscanf(constrain, "@%s=%s", attr, val);
      }
	
      array matches = ({ });
      int cnt = 0;
      foreach(children, object child) {
	// match
	if ( element == "*" || 
	     child->tagname == element || 
	     child->name == element ) 
	{
	  if ( !stringp(attr) || child->attributes[attr] == val ) {
	    cnt++;
	    if ( req_num == -1 || req_num == cnt )
	      matches += ({ child });
	  }
	}
      }
      return matches;
    }
    void join(object node) {
	// this node is joined with the node "node", nodes are identical 
	// check childs of both node
	data = node->get_data();
	foreach( node->get_children(), object rmtChild ) {
	    object matchNode = 0;
	    foreach ( children, object child ) {
		if ( child == rmtChild ) {
		    // join remote node
		    matchNode = rmtChild;
		    child->join(rmtChild);
		}
	    }
	    if ( !objectp(matchNode) ) {
		// add the remote child into our tree
		add_child(rmtChild);
	    }
	}
    }
    
    array(Node) replace_node(string|Node|array(Node) data, void|string xpath) {
	// parse data and replace...
        // remove ?xml at beginning of data;
      array(Node) replacements;

      if ( arrayp(data) )
	replacements = data;
      if ( objectp(data) ) {
	if ( xpath )
	  replacements = data->get_nodes(xpath);
        else
          replacements = ({ data });
      }
      else if ( stringp(data) ) {
	Node node = parse(data);
	if ( !objectp(node) )
	  error("Cannot replace node- unparseable data !");
	if ( xpath )
	  replacements = node->get_nodes(xpath);
	else
	  replacements = ({ node });
      }
      
      father->replace_child(this_object(), replacements);
      return replacements;
    }
  
    string get_xml() {
      return xml.utf8_to_html(dump());
    }
    mapping get_attributes() {
	return attributes;
    }
    string string_attributes() {
      string a = "";
      foreach(indices(attributes), string attr)
	a += attr + "='" + attributes[attr]+ "' ";
      return a;
    }
    string dump() {
      string xml = "";
      xml += "<"+name+" " + string_attributes()+">";
      xml += get_data();
      foreach( children, object child)
	xml+= child->dump();
      xml += "</"+name+">\n";
      return xml;
    }
    int `==(mixed cmp) {
	if ( objectp(cmp) ) {
	    // two nodes are identical if name and attributes match!
	    if ( !functionp(cmp->get_name) || cmp->get_name() != name )
	        return 0;
	    array index = indices(attributes);
            if ( !functionp(cmp->get_attributes) )
                return 0;
	    mapping cmpAttr = cmp->get_attributes();
	    if ( sizeof(index & indices(cmp->get_attributes())) != 
		 sizeof(indices(cmpAttr)) )
		 return 0;
	    foreach ( index, string idx ) {
		if ( attributes[idx] != cmpAttr[idx] )
		    return 0;
	    }
	    return 1; 
	}
	return 0;
    }
    string describe() { return _sprintf(); }
    string _sprintf() { return "Node("+name+"," + sizeof(children)+ " childs, "+
			    (strlen(data) > 0 ? "data": "null")+")"; }
}

class RootNode {
  inherit Node;
  
  mapping pi = ([ ]);
  void add_pi(string name, string data) { 
    if ( arrayp(pi[name]) )
      pi[name] += data;
    else if ( pi[name] )
      pi[name] = ({ pi[name], data });
    else
      pi[name] = data; 
  }
  mixed get_pi() {
    return pi; 
  }
}


class saxHandler
{
    inherit "AbstractCallbacks";

    RootNode root;
    array arr_errors = ({ });
    static ADT.Stack NodeQueue     = ADT.Stack();

    Node get_root() { return root; }

    void create() {
	root = RootNode("root", ([ ]));
	NodeQueue->push(root);
    }

    int store_data(string data) {
      Node active = NodeQueue->pop();
      active->add_data(data);
      NodeQueue->push(active);
      return 1;
    }
    
    string errorSAX(object parser, string err, void|mixed userData) 
    {
      arr_errors += ({ err });
    }

    array get_errors() 
    {
      return arr_errors;
    }
    string get_first_error() 
    {
      if ( sizeof(arr_errors) > 0 )
	return arr_errors[0];
      return 0;
    }

    void startElementSAX(object parser, string name, 
			 mapping(string:string) attrs, void|mixed userData) 
    {
	Node father;
	// connect nodes;
	father = NodeQueue->pop();
	Node active = Node(name, attrs, root, father);
	NodeQueue->push(father);

	NodeQueue->push(active);
	// new element on data queue
    }
    
    
    void endElementSAX(object parser, string name, void|mixed userData)
    {
      Node old = NodeQueue->pop(); // remove old node from queue...
      if ( old->attributes->name == "NAVIGATIONTAB2_CONTENT" )
	werror("Parsed language term: %O\n", old->attributes);
    }
    void cdataBlockSAX(object parser, string value, void|mixed userData)
    {
      store_data(value);
    }
    void charactersSAX(object parser, string chars, void|mixed userData)
    {
	if ( !store_data(chars) )
	    error("Unable to store characters in Node...");
    }
    void commentSAX(object parser, string value, void|mixed userData) 
    {
      store_data("<!--"+value+"-->");
    }
    void referenceSAX(object parser, string name, void|mixed userData)
    {
      werror("referenceSAX(%s)\n", name);
    }
    void entityDeclSAX(object parser, string name, int type, string publicId,
		       string systemId, string content, void|mixed userData)
    {
      werror("entityDecl(%s)\n", name);
    }
    void notationDeclSAX(object parser, string name, string publicId, 
			 string systemId, void|mixed userData) 
    {
        werror("notationDecl(%s)\n", name);
    }
    void unparsedEntityDeclSAX(object parser, string name, string publicId, 
			       string systemId, string notationName, 
			       void|mixed userData) 
    {
        werror("unparsedEntityDecl(%s)\n", name);
    }
    string getEntitySAX(object parser, string name, void|mixed userData)
    {
        werror("getEntitySax(%s)\n", name);
    }
  string processingInstructionSAX(object parser, string name, string data, void|mixed userData)
    {
      root->add_pi(name, data);
    } 
    void attributeDeclSAX(object parser, string elem, string fullname, 
			  int type, int def, void|mixed userData)
    {
        werror("attributeDeclSAX(%s, %s)\n", elem, fullname);
    }
    void internalSubsetSAX(object parser, string name, string externalID, 
			   string systemID, void|mixed uData)
    {
      werror("internalSubset(%s)\n", name);
    }
    void ignorableWhitespaceSAX(object parser, string chars, void|mixed uData)
    {
    }
};

/**
 * Create a mapping from an XML Tree.
 *  
 * @param NodeXML n - the root-node to transform to a mapping.
 * @return converted mapping.
 */
mapping xmlMap(Node n)
{
  mapping res = ([ ]);
  foreach ( n->children, Node children) {
    if ( children->name == "member" ) {
      mixed key,value;
      foreach(children->children, object o) {

	if ( o->name == "key" )
	  key = unserialize(o->children[0]);
	else if ( o->name == "value" )
	  value = unserialize(o->children[0]);
      }
      res[key] = value;
    }
  }
  return res;
}

/**
 * Create an array with the childrens of the given Node.
 *  
 * @param NodeXML n - the current node to unserialize.
 * @return Array with unserialized childrens.
 */
array xmlArray(Node n)
{
    array res = ({ });
    foreach ( n->children, Node children) {
	res += ({ unserialize(children) });
    }
    return res;
}

/**
 * Create an object from its XML representation, id or path tags are possible
 *  
 * @param NodeXML n - the node to unserialize
 * @return the steam object
 */
object xmlObject(Node n)
{
  object node;

  if ( !objectp(n) )
    return 0;
  
  node = n->get_node("id");
  if ( objectp(node) )
    return find_object((int)node->get_data());
  node = n->get_node("path");
  if ( objectp(node) )
    return find_object(node->get_data());
  
#if constant(_Persistence)
  node = n->get_node("group");
  if ( objectp(node) )
    return _Persistence->lookup_group(node->get_data());
  node = n->get_node("user");
  if ( objectp(node) )
    return _Persistence->lookup_user(node->get_data());
#endif
  return 0;
}

/**
 * Create some data structure from an XML Tree.
 *  
 * @param NodeXML n - the root-node of the XML Tree to unserialize.
 * @return some data structure describing the tree.
 */
mixed unserialize(Node n) 
{
    switch ( n->name ) {
    case "struct":
	return xmlMap(n);
	break;
    case "array":
	return xmlArray(n);
	break;
    case "int":
	return (int)n->data;
	break;
    case "float":
	return (float)n->data;
	break;
    case "string":
	return n->data;
	break;
    case "object":
      return xmlObject(n);
      break;
    }
    return -1;
}

Node parse(string|object html)
{
    object cb = saxHandler();
    
    int v = (stringp(html) ? 1:0);
    object sax = xml.SAX(html, cb, ([ ]), 0, v);
    mixed err = catch(sax->parse());
    if ( err != 0 || stringp(cb->get_first_error()) ) 
	throw(({"Error parsing: " + (cb->get_errors()*"\n")+"\n", 
		    (arrayp(err) ? err[1] : backtrace()) }));
    
    Node root =  cb->get_root();
    return root->get_first_child();
}

void test()
{
  string xml = "<?steam config='xmlfile'?><a><b>bb</b><b text='3'>bbb</b><b/><x/><b/><b/></a>";
  string rpl = "<xml><b>xxx&#160;zzz</b><b><![CDATA[yyy&amp;zzz&nbsp;]]></b>"+
    "<b><![CDATA[<img src='test'>IMG</img>]]></b></xml>";
  Node a = parse(xml);
  write("Parsed: " + a->dump()+"\n");
  Node x = a->get_node("x");
  x->replace_node(rpl);
  array nodes = a->get_nodes("b");
  write("Nodes: %O\n", nodes);
  nodes = a->get_nodes("b[@text=3]");
  write("Nodes with text 3: %O\n", nodes);
  nodes = a->get_nodes("/a");
  write("From root = %O\n", nodes);
  write("PI=%O\n", a->get_pi());
  

  xml = "<config><edit><editor name='1'>test</editor><editor name='2'>test2</editor></edit></config>";
  Node cfg = parse(xml);
  // test join operations
  xml = "<config><edit><editor name='3'>test3</editor></edit></config>";
  Node cfg2 = parse(xml);
  cfg->join(cfg2);
  write("Configuration join (editor1,2,3 expected)\n" + cfg->get_xml() + "\n");
  xml = "<config><edit><editor name='2'>newtest2</editor></edit></config>";
  Node cfg3 = parse(xml);
  cfg->join(cfg3);
  write("Another join, overwrite test for configuration edit 2, newtest2 expected !\n" + cfg->get_xml());
      
}
