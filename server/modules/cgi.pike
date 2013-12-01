inherit "/kernel/module";

#include <macros.h>
#include <attributes.h>
#include <database.h>
#include <classes.h>

//! CGI script execution - Calls the system to run programs
//! all available binaries must be available within the sandbox.

static mapping global_env;
static mapping     config;
static object      admins;

//#define CGI_DEBUG

#ifdef CGI_DEBUG
#define DEBUG_CGI(s, args...) write(s, args)
#else
#define DEBUG_CGI(s, args...) 
#endif

#define KILL_DELAY 30

class Wrapper 
{ 
  constant name="Wrapper";
  string buffer = ""; 
  Stdio.File fromfd, tofd, tofdremote; 
  mixed done_cb;

  int close_when_done;
  void write_callback() 
  {
    DEBUG_CGI("CGI:Wrapper::write_callback()\n");

    if(!strlen(buffer)) 
      return;
    int nelems = tofd->write( buffer ); 

    DEBUG_CGI(sprintf("CGI:Wrapper::write_callback(): write(%O) => %d\n",
		    buffer, nelems));

    if( nelems < 0 )
      // if nelems == 0, network buffer is full. We still want to continue.
    {
      buffer="";
      done(); 
    } else {
      buffer = buffer[nelems..]; 
      if(close_when_done && !strlen(buffer))
        destroy();
    }
  }

  void read_callback( mixed id, string what )
  {
    DEBUG_CGI(sprintf("CGI:Wrapper::read_callback(%O, %O)\n", id, what));

    process( what );
  }

  void close_callback()
  {
    DEBUG_CGI("CGI:Wrapper::close_callback()\n");

    done();
  }

  void output( string what )
  {
    DEBUG_CGI(sprintf("CGI:Wrapper::output(%O)\n", what));

    if(buffer == "" )
    {
      buffer=what;
      write_callback();
    } else
      buffer += what;
  }

  void destroy()
  {
    DEBUG_CGI("CGI:Wrapper::destroy()\n");

    catch(done_cb(this_object()));
    catch(tofd->set_blocking());
    catch(fromfd->set_blocking());
    catch(tofd->close());
    catch(fromfd->close());
    tofd=fromfd=0;
  }

  object get_fd()
  {
    DEBUG_CGI("CGI:Wrapper::get_fd()\n");

    /* Get rid of the reference, so that it gets closed properly
     * if the client breaks the connection.
     */
    object fd = tofdremote;
    tofdremote=0;

    return fd;
  }
  

  void create( Stdio.File _f, mixed _done_cb )
  {
    DEBUG_CGI("CGI:Wrapper()\n");

    fromfd = _f;
    done_cb = _done_cb;
    tofdremote = Stdio.File( );
    tofd = tofdremote->pipe( );// Stdio.PROP_NONBLOCK );

    if (!tofd) {
      // FIXME: Out of fd's?
    }

    fromfd->set_nonblocking( read_callback, 0, close_callback );
    
#ifdef CGI_DEBUG
    function read_cb = class
    {
      void read_cb(mixed id, string s)
      {
	DEBUG_CGI(sprintf("CGI:Wrapper::tofd->read_cb(%O, %O)\n", id, s));
      }
      void destroy()
      {
	DEBUG_CGI(sprintf("CGI:Wrapper::tofd->read_cb Zapped from:\n"
			"%s\n", describe_backtrace(backtrace())));
      }
    }()->read_cb;
#else /* !CGI_DEBUG */
    function read_cb = lambda(){};
#endif /* CGI_DEBUG */
    catch { tofd->set_nonblocking( read_cb, 0, destroy ); };
  }


  // override these to get somewhat more non-trivial behaviour
  void done()
  {
    DEBUG_CGI("CGI:Wrapper::done()\n");

    if(strlen(buffer))
      close_when_done = 1;
    else
      destroy();
  }

  void process( string what )
  {
    DEBUG_CGI(sprintf("CGI:Wrapper::process(%O)\n", what));

    output( what );
  }
}

/* CGI wrapper.
**
** Simply waits until the headers has been received, then 
** parse them according to the CGI specification, and send
** them and the rest of the data to the client. After the 
** headers are received, all data is sent as soon as it's 
** received from the CGI script
*/
class CGIWrapper
{
  inherit Wrapper;
  constant name="CGIWrapper";

  string headers="";

  void done()
  {
    if(strlen(headers))
    {
      string tmphead = headers;
      headers = "";
      output( tmphead );
    }
    ::done();
  }

  string handle_headers( string headers )
  {
    DEBUG_CGI(sprintf("CGI:CGIWrapper::handle_headers(%O)\n", headers));

    string result = "", post="";
    string code = "200 OK";
    int ct_received = 0, sv_received = 0;
    foreach((headers-"\r") / "\n", string h)
    {
      string header, value;
      sscanf(h, "%s:%s", header, value);
      if(!header || !value)
      {
        // Heavy DWIM. For persons who forget about headers altogether.
        post += h+"\n";
        continue;
      }
      header = String.trim_whites(header);
      value = String.trim_whites(value);
      switch(lower_case( header ))
      {
       case "status":
         code = value;
         break;

       case "content-type":
         ct_received=1;
         result += header+": "+value+"\r\n";
         break;

       case "server":
         sv_received=1;
         result += header+": "+value+"\r\n";
         break;

       case "location":
         code = "302 Redirection";
         result += header+": "+value+"\r\n";
         break;

       default:
         result += header+": "+value+"\r\n";
         break;
      }
    }
    if(!sv_received)
      result += "Server: "+_Server.get_version()+"\r\n";
    if(!ct_received)
      result += "Content-Type: text/html\r\n";
    return "HTTP/1.0 "+code+"\r\n"+result+"\r\n"+post;
  }

  int parse_headers( )
  {
    DEBUG_CGI("CGI:CGIWrapper::parse_headers()\n");

    int pos, skip = 4;

    pos = search(headers, "\r\n\r\n");
    if(pos == -1) {
      // Check if there's a \n\n instead.
      pos = search(headers, "\n\n");
      if(pos == -1) {
	// Still haven't found the end of the headers.
	return 0;
      }
      skip = 2;
    } else {
      // Check if there's a \n\n before the \r\n\r\n.
      int pos2 = search(headers[..pos], "\n\n");
      if(pos2 != -1) {
	pos = pos2;
	skip = 2;
      }
    }

    output( handle_headers( headers[..pos-1] ) );
    output( headers[pos+skip..] );
    headers="";
    return 1;
  }

  static int mode;
  void process( string what )
  {
    DEBUG_CGI(sprintf("CGI:CGIWrapper::process(%O)\n", what));

    switch( mode )
    {
     case 0:
       headers += what;
       if(parse_headers( ))
         mode++;
       break;
     case 1:
       output( what );
    }
  }
}

void sendfile( string data, object tofd, function done )
{
  object pipe = ((program)"/net/base/fastpipe")();
  pipe->write(data);
  pipe->set_done_callback(done, pipe);
  pipe->output(tofd);
}

class CGIScript
{
  string           command;
  array (string) arguments;
  Stdio.File         stdin;
  Stdio.File        stdout;
  // stderr is handled by run().
  mapping (string:string) environment;
  int                        blocking;

  string priority;   // generic priority
  object|int pid;    // the process id of the CGI script
  Stdio.File ffd;    // pipe from the client to the script

  string tosend = 0;

  mapping (string:int)    limits;
  int uid, gid;  
  array(int) extra_gids;

  void check_pid()
  {
    DEBUG_CGI("CGI:CGIScript::check_pid()\n");

    if(!pid || (objectp(pid) && pid->status()))
    {
      remove_call_out(kill_script);
      destruct();
      return;
    }
    call_out( check_pid, 0.1 );
  }

  Stdio.File get_fd()
  {
    DEBUG_CGI("CGI:CGIScript::get_fd()\n");

    if ( tosend ) { 
      sendfile(tosend, stdin, lambda(int i, mixed q) { stdin=0; });
    }
    else {
      stdin->close();
      stdin=0;
    }

    // And then read the output.
    if(!blocking)
    {
      Stdio.File fd = stdout;
      if( (command/"/")[-1][0..2] != "nph" )
        fd = CGIWrapper( fd,kill_script )->get_fd();
      stdout = 0;
      call_out( check_pid, 0.1 );
      return fd;
    }
    //
    // Blocking (<insert file=foo.cgi> and <!--#exec cgi=..>)
    // Quick'n'dirty version.
    // 
    // This will not be parsed. At all. And why is this not a problem?
    //   o <insert file=...> dicards all headers.
    //   o <insert file=...> does RXML parsing on it's own (automatically)
    //   o The user probably does not want the .cgi rxml-parsed twice, 
    //     even though that's the correct solution to the problem (and rather 
    //     easy to add, as well)
    //
    remove_call_out( kill_script );
    return stdout;
  }

  // HUP, PIPE, INT, TERM, KILL
  static constant kill_signals = ({ signum("HUP"), signum("PIPE"),
				    signum("INT"), signum("TERM"),
				    signum("KILL") });
  static constant kill_interval = 3;
  static int next_kill;

  void kill_script()
  {
    DEBUG_CGI(sprintf("CGI:CGIScript::kill_script()\n"
		    "next_kill: %d\n", next_kill));

    if(pid && !pid->status())
    {
      int signum = 9;
      if (next_kill < sizeof(kill_signals)) {
	signum = kill_signals[next_kill++];
      }
      if(pid->kill)  // Pike 0.7, for roxen 1.4 and later 
        pid->kill( signum );
      else
        kill( pid->pid(), signum); // Pike 0.6, for roxen 1.3 
      call_out(kill_script, kill_interval);
    }
  }

  CGIScript run()
  {
    DEBUG_CGI("CGI:CGIScript::run()\n");

    Stdio.File t, stderr;
    stdin  = Stdio.File();
    stdout = Stdio.File();
    stderr = stdout;

    
    mapping options = ([
      "stdin":stdin,
      "stdout":(t=stdout->pipe()), /* Stdio.PROP_IPC| Stdio.PROP_NONBLOCKING */
      "stderr":(stderr==stdout?t:stderr),
      "cwd": "/",
      "env": environment,
      "noinitgroups":1,
    ]);
    stdin = stdin->pipe(); /* Stdio.PROP_IPC | Stdio.PROP_NONBLOCKING */

    if(!getuid())
    {
      if (uid >= 0) {
	options->uid = uid;
      } else {
	// Some OS's (HPUX) have negative uids in /etc/passwd,
	// but don't like them in setuid() et al.
	// Remap them to the old 16bit uids.
	options->uid = 0xffff & uid;
	
	if (options->uid <= 10) {
	  // Paranoia
	  options->uid = 65534;
	}
      }
      if (gid >= 0) {
	options->gid = gid;
      } else {
	// Some OS's (HPUX) have negative gids in /etc/passwd,
	// but don't like them in setgid() et al.
	// Remap them to the old 16bit gids.
	options->gid = 0xffff & gid;
	
	if (options->gid <= 10) {
	  // Paranoia
	  options->gid = 65534;
	}
      }
      if( !uid )
        FATAL( "CGI: Running "+command+" as root (as per request)" );
    }

    if( limits )
      options->rlimit = limits;
    
    MESSAGE("OPTIONS=%O\n", options);
    MESSAGE("ARGS=%O\n", arguments);
    if(!(pid = run_process( ({ command }) + arguments, options ))) {
      error("Failed to create CGI process.\n");
    }
    // XXX Caudium.create_process returns int (pid number) now
  /*
    if(!objectp(pid)) {
      error("Failed to create CGI process.\n");
    }
    call_out( kill_script, KILL_DELAY*60 );
  */
    return this_object();
  }


  void create( object script, mapping vars, object request, string auth )
  {
    DEBUG_CGI("CGI:CGIScript()\n");

    synchronise_fs(script);
    command = script_to_command(script);
  
    // limits ?

    environment = build_vars(vars);

    string path = "/cgi"+_FILEPATH->object_to_filename(script);

    // todo - encrypt
    environment["HTTP_AUTHORIZATION"] = auth; //"Basic " + MIME.encode_base64(auth);
    environment["REQUEST_METHOD"] = request->request_type;
    if ( request->request_type == "POST" ) {
      environment["CONTENT_LENGTH"] = (string)strlen(request->body_raw);
      tosend = request->body_raw;
    }
    environment["REQUEST_URI"] = path + "?"+request->query;
    environment["QUERY_STRING"] = request->query;
    environment["SCRIPT_NAME"] = request->not_query;
    environment["SCRIPT_FILENAME"] = path;
    environment["DOCUMENT_ROOT"] = "/";
    environment["CONTENT_TYPE"]="application/x-www-form-urlencoded";
    environment["AUTH_TYPE"] = "Basic";

    // bei post eventuell body_raw pipen

    arguments = ({ path });
    
    ffd = request->my_fd;
  }
}

#define VARQUOTE(X) replace(X,({" ","$","-","\0","="}),({"_","_", "_","","_" }))

mapping build_vars(mapping vars)
{
  mapping new = ([]);
  mixed          tmp;

  foreach (indices(vars), tmp) {
    if ( !stringp(vars[tmp]) )
      continue;

    string name = VARQUOTE(tmp);
    if (vars[tmp] && (sizeof(vars[tmp]) < 8192)) {
      /* Some shells/OS's don't like LARGE environment variables */
      new["QUERY_"+name] = replace(vars[tmp],"\000"," ");
      new["VAR_"+name] = replace(vars[tmp],"\000","#");
    }
    
    if (new["VARIABLES"])
      new["VARIABLES"]+= " " + name;
    else
      new["VARIABLES"]= name;
  }
  return new;
}

static mapping files = ([ ]);

mapping get_files() 
{
    return files;
}

static void synchronise_cont(object cont)
{
    string path = _FILEPATH->object_to_filename(cont);
    path = "/cgi"+path;
    if ( !Stdio.mkdirhier(path) )
      steam_error("Cannot create directory: " + path);

    werror("pfad ist %s\n", path);
    werror("synchronise_cont(%O)\n", cont);

    foreach(cont->get_inventory_by_class(CLASS_DOCUMENT), object obj) {
      int modified = obj->query_attribute(DOC_LAST_MODIFIED);
      if ( modified > files[obj] ) {
	Stdio.write_file(path + "/"+ obj->get_identifier(), obj->get_content());
	files[obj] = modified;
      }
    }
    foreach(cont->get_inventory_by_class(CLASS_CONTAINER), object folder) {
	synchronise_cont(folder);
    }
}

static void synchronise_fs(object script)
{
    //Stdio.write_file("cgi/"+script->get_identifier(), script->get_content());
    synchronise_cont(script->get_environment());
}


string script_to_command(object script)
{
  return get_program(script->query_attribute(DOC_MIME_TYPE));
}


object call_script(object script, mapping vars, object req)
{
  object user = this_user();
  object owner = script->get_creator();
  if ( !admins->is_member(owner) )
      steam_error("Cannot run non-root scripts !");

  string auth = user->get_identifier() + ":" +user->get_ticket();
  return CGIScript(script, vars, req, auth)->run()->get_fd();
}

mapping get_programs()
{
  return copy_value(config);
}

string get_program(string mtype)
{
  if ( !stringp(mtype) )
    return 0;

  sscanf(mtype, "application/%s", mtype);
  return config[mtype];
}

void init_module() 
{
  string cfg = Stdio.read_file(_Server->query_config("config-dir")+"/cgi.txt");
  
  if ( stringp(cfg) )
    config = read_config(cfg, "cgi");
  else
    config = ([ ]);
  

#if 0
  if ( !Stdio.is_dir("server/cgi") )
    mkdir("server/cgi");
  if ( !Stdio.is_dir("server/cgi/bin") )
    mkdir("server/cgi/bin");
#endif

  admins = GROUP("admin");
  global_env = ([ ]);
  global_env["SERVER_NAME"]=_Server->get_server_name();
  global_env["SERVER_SOFTWARE"]=_Server->get_version();
  global_env["GATEWAY_INTERFACE"]="CGI/1.1";
  global_env["SERVER_PROTOCOL"]="HTTP/1.0";
  global_env["SERVER_URL"]="/";
}


string get_identifier() { return "cgi"; } 




