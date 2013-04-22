inherit Service.Service;

Thread.Queue oQueue = Thread.Queue();
Thread.Mutex mBuffer = Thread.Mutex();
string sStripBuffer;

object persistence_module;
int content_in_database;
int content_in_filesystem;

object tStripDemon;
mapping mStripFilter = ([  ]);
mapping mLimits = ([ ]); 
Sql.Sql handle;

#include <events.h>
#include <attributes.h>
#include <configure.h>

class Doc {
  int content_id;
  int id;
  string mime;
  string name;
  
  void create(object|int o) { 
    if ( objectp(o) ) {
      mime = o->query_attribute(DOC_MIME_TYPE);
      name = o->get_identifier();
      //werror("Mimetype for %s is %O\n", name, mime);
      id = o->get_object_id();
      content_id = o->get_content_id();
    }
    else {
      id = o;
      string query = "SELECT ob_data from ob_data where ob_attr='CONTENT_ID' AND ob_id='"+id+"'";
      array doc_id = handle->query(query);
      if ( sizeof(doc_id) > 0 )
	content_id = (int)doc_id[0]->ob_data;
      query = "SELECT obmimetype, obname from ob_class where ob_id='"+id+"'";
      array data = handle->query(query);
      if ( sizeof(data) > 0 ) {
	mime = data[0]->obmimetype;
	name = data[0]->obname;
      }
    }
  }
}

void notify(mapping event)
{
    //werror("EVENT_UPLOAD in fulltext.pike [%O]\n" , event);
    if (!tStripDemon)
        tStripDemon = thread_create(strip_demon);
    Doc doc = Doc(event->object);
    oQueue->write(doc);
}

void update_index(int force) 
{
  string query = "SELECT ob_id from ob_class where obmimetype!=''";
  Sql.sql_result result = handle->big_query(query);
  array documents = allocate(result->num_rows());
  for (int i=0; i<result->num_rows(); i++) {
    array fetched_line = result->fetch_row();
    documents[i] = (int)fetched_line[0];
  }
  if (!force) {
    query = "SELECT distinct ob_id from doc_ft";
    result = handle->big_query(query);
    array indexed = allocate(result->num_rows());
    for (int i=0; i<result->num_rows(); i++) {
      array fetched_line = result->fetch_row();
      indexed[i] = (int)fetched_line[0];
    }
    documents -= indexed;
  }
  foreach(documents, int d) {
    oQueue->write(Doc(d));
  }
}

void call_service(object user, mixed args, int|void id)
{
    werror("Service called with %O\n", args);
    if (args->update_index) {
      update_index(args->force);
    }
    if (args->update_document) {
      oQueue->write(Doc(args->document));
    }
}

static void run()
{
  handle = Sql.Sql(serverCfg["database"]);
}

void strip_demon() {
    werror( "[%s] Content Strip Service Demon started.\n", timelib.log_time() );
    while (1) {
      mixed err = catch {
        string query;

        Doc oDocument = oQueue->read();
        string sMime = oDocument->mime;
        string sStripHandler;
	
	sStripHandler = mStripFilter[sMime];
	
	if ( sStripHandler )
	{
            int iContentID = oDocument->content_id;
            int iObID = oDocument->id;
            Stdio.File content_file;
            string content_file_path;
            if ( content_in_filesystem ) {
              content_file_path = send_cmd( persistence_module, "get_content_path",
                                            ({ iContentID, 1 }) );
              if ( stringp(content_file_path) )
                catch( content_file = Stdio.File( content_file_path, "r" ) );
            }
            if ( !objectp(content_file) && content_in_database ) {
              Stdio.File temp = Stdio.File("buffer.file", "rwct");
              Sql.sql_result res =
                handle->big_query("select rec_data from doc_data where "+
                                  "doc_id = "+iContentID+
                                  " order by rec_order");
              while (mixed data = res->fetch_row())
                temp->write(data[0]);
              temp->close();
              content_file_path = "buffer.file";
              content_file = Stdio.File( content_file_path );
            }
            if ( ! objectp(content_file) ) {
              werror( "Could not get content %d for object %d\n", iContentID, iObID );
              continue;
            }

            //werror("Size of Buffer is " + Stdio.file_size( content_file_path )+"\n");
            if ( strlen(sStripHandler) > 0 ) {
              Stdio.File outfile = Stdio.File("strip.file","wct");
              mixed err = catch {
                int PCode = Process.create_process(
                                                   ({ sStripHandler }),
                                                   ([ "stdin" : content_file,
                                                      "stdout" : outfile,
                                                      "rlimit": mLimits, ])
                                                   )->wait();
                werror( "[%s] Stripped content length of %s (#%d, %s, "
                        + "content %d: %s) is %d bytes\n",
                        timelib.log_time(), oDocument->name, iObID,
                        oDocument->mime, iContentID, content_file_path,
                        Stdio.file_size("strip.file") );
              };
              if (err)
                werror( "[%s] Error during content stripping:\n%s\n",
                        timelib.log_time(),
                        master()->describe_backtrace(err) );
	      outfile->close();
              content_file->close();
	      outfile->open("strip.file","r");
	      query = "replace into doc_ft values("+iObID+","+
                iContentID+",\""+
                handle->quote(outfile->read())+"\")";
	    }
	    else {
	      string cbuffer = Stdio.read_file( content_file_path );
	      werror("[%s] Updating index of %s (#%d, %s, content %d: %s): %d bytes...\n",
                     timelib.log_time(), oDocument->name, iObID, oDocument->mime, iContentID,
                     content_file_path, strlen(cbuffer) );
	      query = "replace into doc_ft values(" + iObID + "," + iContentID + ",\"" +
                handle->quote(cbuffer) + "\")";
	    }
	    handle->big_query(query);
        }
        else
	  werror("[%s] No Striphandler configured for %O (%O)\n", 
		 timelib.log_time(), oDocument->name, sMime);
      };
      if ( err )
        werror( "[%s] Exception: %O\n%O\n",
                timelib.log_time(), err[0], err[1] );
    }
}

mixed search_documents(string pattern)
{
    object handle = Sql.Sql(serverCfg["database"]);
    object result =  handle->big_query("select ob_id, match(doc_data) against(%s) from doc_ft where match(doc_data) against(%s)", pattern, pattern);
    array res = ({});
    mixed row;
    while (row = result->fetch_row())
        res += ({ row });

    return res;
}


static void create_table(string dbhandle)
{
    Sql.Sql handle = Sql.Sql(dbhandle);
    handle->query("create table if not exists doc_ft (ob_id int, "+
                  "doc_id int, doc_data TEXT, FULLTEXT(doc_data))");
}


/*
 * create temporary table ft_id (ob_id int primary key, count int);
 * insert into ft_id select ob_id, 0 from ob_data where ob_attr='DOC_MIME_TYPE' and ob_data='"text/html"';
 * replace into ft_id select ob_id, 1 from doc_ft;
 * delete from ft_id where count = 1;
 */
static void check_ft_integrity()
{
    Sql.Sql handle = Sql.Sql(serverCfg["database"]);
    handle->query("create temporary table ft_id "+
                  "(ob_id int primary key, count int)");
    handle->query("insert into ft_id select distinct "+
                  "ob_id,0 from ob_data where ob_attr='DOC_MIME_TYPE'"+
                  "and ob_data='\""+
                  indices(mStripFilter)*"\"' or ob_data='\""+"\"'");
    handle->query("replace into ft_id select distinct ob_id, 1 from doc_ft");
    handle->query("delete from ft_id where count =1");
    array missing = handle->query("select distinct ob_id from ft_id");
    handle->query("drop table ft_id");
    foreach (missing, mixed a)
    {
        object o = connection->find_object((int)a["ob_id"]);
        if (objectp(o))
            oQueue->write(Doc(o));
    }
}

static private void got_kill(int sig)
{
    _exit(1);  
}

int main(int argc, array argv)
{
    init( "fulltext", argv + ({ "--eid="+EVENT_UPLOAD }) );

    if (catch{mStripFilter = read_config_file(CONFIG_DIR+"/services/fulltext.cfg");})
      mStripFilter = ([ "text/html" : "html2text" ]);

    if ( !mStripFilter["text/plain"]) 
      mStripFilter["text/plain"] = "";

    // check strip filters and remove any that don't work:
    foreach ( indices(mStripFilter), string mime ) {
      mixed executable = mStripFilter[ mime ];
      if ( !stringp(mime) || !stringp(executable) || executable == "" )
        continue;
      mixed err = catch {
        Process.create_process( ({ executable }), ([ ]) )->wait();
      };
      if ( err ) {
        werror( "[%s] Executable for %s strip filter not working: %s (Error: %s)\n",
                timelib.log_time(), mime, executable, err[0]-"\n" );
        m_delete( mStripFilter, mime );
      }
    }

    signal(signum("QUIT"), got_kill);
    
    mixed err = catch{
        create_table(serverCfg["database"]);
        start();
        persistence_module = send_cmd( 0, "get_module", "persistence" );
        content_in_database = send_cmd( persistence_module, "get_store_content_in_database", 0 );
        content_in_filesystem = send_cmd( persistence_module, "get_store_content_in_filesystem", 0 );
    };

    tStripDemon = thread_create(strip_demon);
    thread_create(check_ft_integrity);

    if (err)
        werror("Startup of fulltext service failed.\n"+
               master()->describe_backtrace(err)+"\n");
    return -17;
}

mapping read_config_file(string fname)
{
    Parser.XML.Tree.Node node = Parser.XML.Tree.parse_file(fname);
    if (!objectp(node))
        error("Failed to parse config file %s\n", fname);

    mapping data = ([]);
    node = node->get_first_element("config");
    foreach(node->get_elements(), Parser.XML.Tree.Node n)
    {
	mapping attributes = n->get_attributes();
	switch ( n->get_tag_name() ) {
	case "doc_strip":
	    if ( !stringp(attributes->mime) ) 
		error("Missing mime attribute for doc_strip in config file!");
	    data[attributes["mime"]] = n->get_last_child()->get_text();
	    break;
	case "limits":
	    foreach(n->get_elements(), Parser.XML.Tree.Node l) {
		int lsz = (int)l->get_last_child()->get_text();
		werror( "[%s] Using Limit: " + l->get_tag_name() + " = "+ lsz +"\n",
                        timelib.log_time() );
		mLimits[l->get_tag_name()] = lsz;
	    }
	    break;
	default:
            werror( "[%s] Unknown Tag in Config file : " + n->get_tag_name() +"\n",
                    timelib.log_time() );
	}
    }
    return data;
}
