inherit "handle";

#include <macros.h>

string describe() { return "PostgresHandle"; }

array list_tables() {
  string a, b;
  array result = oHandle->list_tables() || ({ });
  array tables = ({ });
  foreach( result, string tname ) {
    sscanf(tname, "%s_key%s", a, b);
    if ( search(tname, "sql_") != 0 && 
	 search(tname, "_pkey") == -1 &&
	 search(tname, "_key") == -1 &&
	 search(tname, "_i_") == -1 )
      tables += ({ tname });
  }
  return tables;
}

string quote_index(mixed index) {
  if ( !stringp(index) )
    return index;
  return oHandle->quote(string_to_utf8(lower_case(utf8_to_string(index))));
}

string create_insert_statement(array sStatements)
{
  string s = "";
  foreach(sStatements, string statement) {
    s+= "insert into ob_data values " + statement + ";";
  }
  return s;
}

void check_tables() { }

void create_table(string name, array types)
{
  string query = "create table " + name + " (";
  for ( int i = 0; i < sizeof(types) - 1; i++ ) {
    mapping type = types[i];
    query += type->name + " " + type->type + ",";
  }
  query += types[sizeof(types)-1]->name + " " + types[sizeof(types)-1]->type;
}

mapping check_updates(object dbupdates, function update_classtableobject) 
{
  return ([ ]);
}

string escape_blob(string data)
{
  return replace(data, ({ "\0", "\\", "'" }), 
		 ({ "\\\\000", "\\\\134", "\\\\047" }));
}

string unescape_blob(string data)
{
  return replace(data, ({ "\\\\000", "\\\\134", "\\\\047" }), 
		 ({ "\0", "\\", "'" }));
}

string get_database() { return "postgres"; }

void create_tables()
{
    MESSAGE("creating table \"doc_data\" ");
    oHandle->big_query("create table doc_data ("+
		       " rec_data bytea, "+
		       " doc_id int, "+
		       " rec_order int, "+
		       " primary key (doc_id, rec_order)"+
		       ") ");
    MESSAGE("creating table \"ob_class\" ");
    oHandle->big_query("create table ob_class ("+
		       " ob_id int primary key, "+
		       " ob_class text, "+
		       " obkeywords text, "+
		       " obname text, "+
		       " obdescription text, "+
		       " obmimetype text, " +
		       " obversionof text "+
		       ")");

    oHandle->query("create index _i_obdescription on ob_class (obdescription)");
    oHandle->query("create index _i_obkeywords on ob_class (obkeywords)");
    oHandle->query("create index _i_obname on ob_class (obname)");
    oHandle->query("create index _i_obmimetype on ob_class (obmimetype)");
    oHandle->query("create index _i_obversionof on ob_class (obversionof)");

    MESSAGE("creating table \"ob_data\" ");
    oHandle->big_query("create table ob_data ("+
		       " ob_id int, "+
		       " ob_ident text,"+
		       " ob_attr text, "+
		       " ob_data text,"+
		       " unique(ob_id, ob_ident, ob_attr)"+
		       ")");

    oHandle->query("create index _i_obdata on ob_data (ob_ident, ob_attr, ob_data)");

    MESSAGE("creating table \"variables\" ");
    oHandle->big_query("create table variables ("+
		       " var text primary key, "+
		       " value int"+
		       ")");
}

