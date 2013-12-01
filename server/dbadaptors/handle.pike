#include <macros.h>
#include <database.h>

Sql.Sql oHandle;
private string db_connect;

void keep() {
  Sql.sql_result res =
    oHandle->big_query("select ob_class from ob_class "+
		       "where ob_id = 13");
  res->fetch_row();
}

void create(string connect) {
  db_connect = connect;
  oHandle = Sql.Sql(db_connect);
}

int|object big_query(object|string q, mixed ... extraargs) {
  Sql.sql_result res;

  string query = q;
  if ( arrayp(extraargs) && sizeof(extraargs)>0) 
    query = sprintf(q, @extraargs);
    
  mixed err = catch { res=oHandle->big_query(query); };
  if (err)
    {
      FATAL("Database Error ("+(string)oHandle->error()+")\n"+
	    master()->describe_backtrace(err));
      throw(err);
    }
  return res;
}

array list_tables() {
  return oHandle->list_tables() || ({ });
}

array(mapping(string:mixed)) query(object|string q, mixed ... extraargs) {
  array(mapping(string:mixed)) res;
  string query = q;
  if ( arrayp(extraargs) && sizeof(extraargs)>0) 
    query = sprintf(q, @extraargs);

  mixed err = catch ( res=oHandle->query(query) );
  if (err) {
      FATAL(" SQL Problem: SQL=" + query + "\n"+
	    " Database Error("+(string)oHandle->error()+")");
      destruct(oHandle);
      oHandle = Sql.Sql(db_connect);
      res = oHandle->query(q, @extraargs);
  }
  return res;
}

mapping get_indices(string tname) {
  mixed result = ([ ]);
  mixed res = oHandle->query("show index from ob_data");
  werror("get_indices() = %O\n", res);
  return result;
}


void check_tables() { }

void create_tables() { }

string create_insert_statement(array sStatements)
{
  string s = sStatements * ",";
  return "insert into ob_data values " + s;
}

void create_table(string name, array types)
{
  string query = "create table " + name + " (";
  for ( int i = 0; i < sizeof(types) - 1; i++ ) {
    mapping type = types[i];
    query += type->name + " " + type->type + ",";
  }
  query += types[sizeof(types)-1]->name + " " + types[sizeof(types)-1]->type;

  array unique = ({ });
  foreach( types, mapping type ) {
    if ( type->unique )
      unique += ({ type->name });
  }
  if ( sizeof(unique) > 0 ) {
    query += ", UNIQUE(" + (unique*",")+")";
  }
  query += ")";
}

string escape_blob(string data) {
  return oHandle->quote(data);
}

string unescape_blob(string data) {
  return data;
}

string quote_index(string index) {
  if ( !stringp(index) )
    return index;
  return oHandle->quote(index);
}

int enable_decorations() { return 0; }
int get_object_class() { return 0; }
object get_object() { return _Database; }
object this() { return _Database; }

string get_database() { return "mysql"; }

mapping check_updates(object dbupdates, function func) { return ([ ]); }

function `->(string fname) {
  switch(fname) {
  case "query": return query;
  case "big_query" : return big_query;
  case "keep": return keep;
  case "list_tables": return list_tables;
  case "create_tables": return create_tables;
  case "check_tables": return check_tables;
  case "create_insert_statement": return create_insert_statement;
  case "create_table": return create_table;
  case "check_updates": return check_updates;
  case "unescape_blob": return unescape_blob;
  case "escape_blob": return escape_blob;
  case "get_database": return get_database;
  case "quote_index": return quote_index;
  case "get_object_class": return get_object_class;
  case "get_object": return get_object;
  case "enable_decorations": return enable_decorations;
  case "this": return this;
  case "describe": return describe;
  default : 
    if ( !objectp(oHandle) ) {
      return 0;
    }
    return oHandle[fname];
  }
}

string describe() { return "SqlHandle()"; }

