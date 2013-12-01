class Return {
    function resultFunc = 0;
    function processFunc = 0;
    int webservice = 0;
    mixed userData = 0;

    int tid, oid, oclass, cmd;
    int id;
    mapping vars;
    string mimetype = "text/plain";
    
    void set_request(object request) {
    }

    void asyncResult(mixed _id, mixed result) {
	if ( functionp(processFunc) ) {
	    if ( userData ) 
		result = processFunc(result, userData);
	    else
		result = processFunc(result);
	}
        if ( functionp(resultFunc) )
	resultFunc(this_object(), result);
    }
    int is_async_return() { return 1; }
}

class HtmlHandler {
    inherit Return;

    string header = "HTTP/1.1 200 OK\r\nServer: sTeam HTTP\r\nContent-Type: text/html; charset=utf-8\r\nConnection: keep-alive\r\nDate: "+
    httplib.http_date(time())+"\r\n\r\n";
    string head, foot;
    object _fd;
    function htmlResultFunc;
    
    Return asReturn;

    void create(function f, void|object asReturnObj, void|mapping vars) { 
      htmlResultFunc = f; 
      if ( objectp(asReturnObj) ) {
	  set_return_object(asReturnObj);
	  if ( mappingp(vars) )
	      asReturnObj->vars = vars;
      }
    }

    void set_return_object(object asReturnObj) {
	if ( !objectp(asReturnObj) )
	    return;
	asReturn = asReturnObj;
	asReturn->resultFunc = asyncResult;
    }
    
    string set_html(string headHTML, string footHTML) {
	head = headHTML;
	foot = footHTML;
    }

    void set_request(object request) {
	_fd = request->my_fd;
	if ( stringp(header) ) {
	  _fd->write(header);
	  if ( stringp(head) ) 
	    _fd->write(head);
	  header = 0;
	}
    }
  
    void output(string str) {
      if ( objectp(_fd) ) {
	if (stringp(header) )
	  steam_error("Unable to output, when header is not send !");

	_fd->write(str);
      }
    }

    void asyncResult(mixed id, mixed result) {
	if ( functionp(htmlResultFunc) )
	    result = htmlResultFunc(id, result);
	_fd->write(result);
	if ( !objectp(asReturn) || id == asReturn ) {
          if ( stringp(foot) && strlen(foot) > 0 )
	    _fd->write(foot);
          _fd->close();
	}
    }
}
