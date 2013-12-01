class Handler {
    inherit "AbstractCallbacks";

    static string    output = ""; // the output
    static mapping rxml_handlers   = ([ ]);
    static mapping rxml_attributes = ([ ]);

    static string node_data;
    static function node_handler = 0;

    void store_data(string data) {
	node_data += data;
    }
    
    void startElementSAX(object parser, string name, 
			 mapping(string:string) attrs, void|mixed userData) 
    {
	werror("startElementSax("+name+")\n");
	werror("Parser Mapping:%O\n", attrs);
	if ( !rxml_handlers[name] )
	    output += "<"+name+">";
	else {
	    rxml_attributes[name] = attrs;
	    node_handler = store_data;
	}
    }
    void endElementSAX(object parser, string name, void|mixed userData)
    {
	werror("endElementSax("+name+")\n");
	function hfunc = rxml_handlers[name];
	mapping attr = rxml_attributes[name];

	if ( functionp(hfunc) ) {
	    output += hfunc(attr, node_data);
	    node_handler = 0;
	    node_data = "";
	}
	else
	    output += "</"+name+">";

	node_data = "";
    }
    void cdataBlockSAX(object parser, string value, void|mixed userData)
    {
	output += value;
    }
    void charactersSAX(object parser, string chars, void|mixed userData)
    {
	werror("data(%s)\n", chars);
	if ( functionp(node_handler) )
	    node_handler(chars);
	else
	    output += chars;
    }
  void errorSAX(object parser, string err, void|mixed userData) {
    werror("Error(%s)", err);
  }
  
    void set_handlers(mapping h) {
	rxml_handlers = h;
    }
    string get_result() {
	return output;
    }
}

string test(mapping attributes, string data)
{
    return "abc";
}

void main(int argc, array argv)
{
    object cb = Handler();
    if ( argc > 1 ) {
	string content = Stdio.read_file(argv[1]);
	cb->set_handlers(([ ]));
	object sax = xml.HTML(content, cb, ([ ]), 0, 1);
	sax->parse();
	return;
    }
    string html = "<html><body><h2>test</h2> hoops hoops! <oops heckmeck='1'>xml</oops></html>";
    mapping h = ([ "oops": test, ]);
    cb->set_handlers(h);
    object sax = xml.HTML(Stdio.read_file("xmltest.xml"), cb, ([ ]), 0, 1);
    sax->parse();
    write(cb->get_result()+"\n");
    object x = xml.SAX(html, cb, ([ ]), 0, 1);
    mixed err = catch(x->parse());
}





