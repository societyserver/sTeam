inherit Service.Service;

#include <events.h>


//#define DEBUG_SEARCH 1

#ifdef DEBUG_SEARCH
#define SEARCH_LOG(s, args...) werror("search: "+s+"\n", args)
#else
#define SEARCH_LOG(s, args...)
#endif


string low_compose_value(array value)
{
 switch ( value[0] ) {
   case ">":
   case "<":
   case "=":
     sscanf(value[1], "\"%s\"", value[1]);
     return value[0]+" '" + value[1]+"'";
     break;
   case "like":
   default:
     sscanf(value[1], "\"%s\"", value[1]);
     return value[0]+" '" + value[1]+"'";
 }
}

string compose_value_expression(mapping st)
{
 string query;
 if ( st->storage == "attrib" ) 
   query = " (ob_ident = 'attrib' and ob_attr='"+st->key+"' and ob_data "+
     st->value[0]+" '"+st->value[1]+"') ";
 else if ( st->storage == "doc_ft" ) 
   query = " (match(doc_data) against ('"+st->value +"')) ";
 else {
   query = " (ob_ident = '"+st->storage+"' and ob_attr='"+st->key+
     "' and ob_data ";
   query += low_compose_value(st->value) + ") ";
 }
 return query;
}

string compose_value_expressions(array tokens, string andor)
{
 string query = "";

 mapping last = tokens[0];
 string exp = compose_value_expression(last);

 for ( int i = 1; i < sizeof(tokens); i++ ) {
   mapping token = tokens[i];
   query += exp + " " + andor + " ";
   exp = compose_value_expression(token);
 }
 query += exp;
  
 return query;
}

mixed run_query(object handle, string query)
{
 SEARCH_LOG("Query: %s\n", query);
 return handle->big_query(query);
}


void call_service(object user, mixed args, int|void id)
{
 SEARCH_LOG("Search Service called with %O\n", args);
 object handle = Sql.Sql(serverCfg["database"]);

 if ( sizeof(handle->list_tables("temp_search")) )
   handle->big_query("drop table temp_search");

 array res = ({});
 array classes, extends, limits, fulltext;
 int maxresults, startresults;

 if ( mappingp(args) ) {
   classes = args->classes;
   extends = args->extends;
   limits = args->limits;
   fulltext = args->fulltext;
   maxresults = args->maxresults;
   startresults = args->startresults;
 }
 else {
   classes = args[2] || ({ "/classes/Object.pike" });
   extends = args[3] || ({ });
   limits = args[4] || ({ });
   fulltext = args[5];
 }
 int keywordsearch = 0;
  
 string _query;
 array limitkeys = ({ });
 array extendkeys = ({ });
 foreach(limits, mapping l) {
   limitkeys += ({ l->key });
 }
 foreach(extends, mapping e) {
   extendkeys += ({ e->key });
 }

 // make sure class names are quoted:
 for ( int i=0; i<sizeof(classes); i++ ) {
   if ( !has_prefix( classes[i], "\"" ) &&
        !has_prefix( classes[i], "'" ) )
     classes[i] = "\"" + classes[i];
   if ( !has_suffix( classes[i], "\"" ) &&
        !has_suffix( classes[i], "'" ) )
     classes[i] += "\"";
 }

 if ( equal(classes, ({ "\"/classes/User\"" })) &&
      sizeof(extendkeys-({"OBJ_NAME", "USER_FIRSTNAME", "USER_EMAIL", "USER_FULLNAME" })) == 0 )
 {
   mapping keymap = ([ "OBJ_NAME": "login", 
			"USER_FIRSTNAME":"firstname",
			"USER_FULLNAME":"lastname",
			"USER_EMAIL":"email", ]);
   string key, val;
   _query = "select distinct ob_id from i_userlookup where ";
   for ( int i = sizeof(extends) - 1; i >= 0; i-- ) {
     key = extends[i]->key;
     if ( !keymap[key] ) continue;
     val = low_compose_value(extends[i]->value);
     _query += " "+ keymap[key]+" " + val + (i>0?" OR ":"");
   }
   keywordsearch = 1;
 }
 else if ( equal(classes, ({ "\"/classes/Group\"" })) &&
	sizeof(extendkeys-({"GROUP_NAME"})) == 0 )
 {
   mapping keymap = ([ "GROUP_NAME": "k", ]);
   string key, val;
   _query = "select distinct substring(v,2) from i_groups where ";
   for ( int i = sizeof(extends) - 1; i >= 0; i-- ) {
     key = extends[i]->key;
     if ( !keymap[key] ) continue;
     val = low_compose_value(extends[i]->value);
     _query += " "+ keymap[key]+" " + val + (i>0?" OR ":"");
   }
   keywordsearch = 1;
 }
 else if ( sizeof(limitkeys) == 0 && sizeof(extendkeys) == 0 && sizeof(fulltext) > 0)
 {
     keywordsearch = 1;
     _query = "select ob_id from doc_ft where " + 
	    compose_value_expressions(fulltext, "or");
 }
 else if ( (sizeof(limitkeys-({"OBJ_VERSIONOF","DOC_MIME_TYPE"})) == 0 ) &&
      (sizeof(extendkeys-({ "OBJ_NAME", "OBJ_DESC", "OBJ_KEYWORDS" })) == 0))
 {
     // this is the new searching in the optimized ob_class table
     keywordsearch = 1;
     _query = "select distinct ob_id from ob_class where (";
     array searchterms = ({ });
     foreach(extends, mapping e) {
       //string sterm = low_compose_value(e->value);
       if ( !arrayp(e->value) )
	  e->value = ({ "like", e->value });
       string sterm = "against ('" + replace(e->value[1], "%", "")+"')";
       if ( search(searchterms, sterm) == -1 )
	  searchterms += ({ sterm });
     }
     if ( search(extendkeys, "OBJ_NAME") >= 0 && 
	   search(extendkeys, "OBJ_DESC") >= 0 &&
	   search(extendkeys, "OBJ_KEYWORDS") >= 0 ) {
       for ( int i = sizeof(searchterms) - 1; i >= 1; i-- )
	  _query += " match(obkeywords) " + searchterms[i] + " OR ";
       _query += "match(obkeywords) " + searchterms[0] + ")";
     }
     else {
       mapping keymap = ([ "OBJ_NAME": "obname", 
		  	  "OBJ_DESC": "obdescription",
			  "OBJ_KEYWORDS": "obkeywords",
                         "DOC_MIME_TYPE": "obmimetype"]);
       string key, val;
     for ( int i = sizeof(extends) - 1; i >= 0; i-- ) {
 	  key = extends[i]->key;
	  if ( key=="OBJ_KEYWORDS" ) {
	    _query += "(";
	    for ( int i = sizeof(searchterms) - 1; i >= 1; i-- )
	      _query += " match(obkeywords) " + searchterms[i] + " OR ";
	    _query += "match(obkeywords) " + searchterms[0] + ")";
	  }
	  else {
	    val = low_compose_value(extends[i]->value);
	    _query += " "+ keymap[key]+" " + val + (i>0?" OR ":"");
	  }
       }
       _query += ")";
     }

     _query += " AND obversionof=0 ";
     // and all classes
     if ( sizeof(classes) > 0 ) {
       string orclasses = classes * " OR ob_class=";
       _query += " AND (ob_class="+ orclasses + ")";
     }

     if ( search(limitkeys, "DOC_MIME_TYPE") >= 0 ) {
       // and mimetype !
       foreach(limits, mapping l) {
	      if ( l->key == "DOC_MIME_TYPE" ) {
	        string val = low_compose_value(l->value);
	        _query += " AND obmimetype "+val;
	      }
       }
      // end new searching - (else old and slow searching)
     }
     if ( sizeof(fulltext) > 0 ) {
       _query += " UNION select ob_id from doc_ft where " + 
	      compose_value_expressions(fulltext, "or");
     }

 }
 else {
   // slow searching
   if ( sizeof(fulltext) ) {
     _query = "create table temp_search as select ob_id from ( doc_ft ";
     classes = ({ }); // classes are documents
   }
   else
     _query = "select distinct ob_data.ob_id from ( ob_data ";
   if ( arrayp(classes) && sizeof(classes) > 0 ) {
     _query += "INNER JOIN ob_class on ob_class.ob_id=ob_data.ob_id and ("+
	( "ob_class = "+classes*" or ob_class=")+")";
   }  
   _query += ") where";
    
    if ( sizeof(fulltext) )
      _query += compose_value_expressions(fulltext, "or");
    else
      _query += compose_value_expressions(extends, "or");
  }
  object result;

 result = run_query(handle, _query);  
  
 if ( sizeof(fulltext) > 0 && keywordsearch==0 ) {
     _query = "select distinct ob_id from temp_search";
     result = run_query(handle, _query);
 }


 mixed row;
 while (row = result->fetch_row()) {
   if ( !arrayp(row) )
     row = ({ row });
   foreach(row, int oid) {
     int ok = 1;
     // check limits here
     if ( !keywordsearch ) {
	foreach ( limits, mapping limit ) {
	  _query = "select distinct ob_id from ob_data where ob_id="+oid+" and "+
	    compose_value_expression(limit);
	  object lres = run_query(handle, _query);
	  if ( !lres->fetch_row() ) {
	    ok = 0;
	  }
	}
     }
     if ( ok ) 
	res += ({ oid });
   }
 }
 SEARCH_LOG("Result is %O\n",res);
 int resultsize = sizeof(res);
 if ( startresults > 0 ) {
   startresults = max(startresults, resultsize);
   res = res[startresults..];
 }
 if ( maxresults > 0 ) {
   res = res[..maxresults-1];
 }
 async_result(id, res);
}

static void run()
{
}

static private void got_kill(int sig)
{
   _exit(1);  
}

int main(int argc, array argv)
{
 signal(signum("QUIT"), got_kill);
 init( "search", argv );
 start();
 return -17;
}
