/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 * 
 * $Id: db_n_one.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 */

constant cvs_version="$Id: db_n_one.pike,v 1.2 2009/05/06 19:23:10 astra Exp $";


/*
 *  $Id: db_n_one.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 *  Database Table with non unique indexing abilities,
 *  result of a query is always an array of keys
 *
 */

#include <macros.h>


private static string          sDbTable;
private static function             fDb;

string tablename()
{
    return copy_value(sDbTable);
}

/**
 * connect a db_n_one table with the according database table
 * from database.pike
 *
 * @param  none
 * @author Ludger Merkens
 */
static final void load_db_mapping()
{
    // get database access function and tablename

    [fDb , sDbTable]= _Database->connect_db_mapping();
    
    // we are in secure code, so create table according to
    // values from database.
    if( search(fDb()->list_tables(), "mi_"+sDbTable ) == -1 ) 
    {
	fDb()->big_query("create table mi_"+sDbTable+
                         "(k char(255) not null, v text,"+
			 (fDb()->get_database() == "postgres" ?
			  "unique(v))" : "unique(v(60)))"));
        //FIXME: postgres needs this as:
        //(k char(255) not null, v text unique)
    }
}
    
/**
 * get a list of all values associated with
 * @param   string key  - the key to access
 * @result  mixed value - the datastructure set with `[]= if any
 */
static mixed get_value(string|int key) {
    mixed d = ({});
    mixed row;

    //    LOG("search "+sDbTable +" for "+ (string) key);
    Sql.sql_result res =
	fDb()->big_query("select v from mi_"+sDbTable+
                         " where k like '"+fDb()->quote_index(key)+"'");
    while (res && (row=res->fetch_row()))
        d+= ({ unserialize(row[0])});
    destruct(res);
    return d;
}
    
/**
 * Add an entry into the list, there is no duplicate check
 * The serialization of the given value will be stored to the database
 * @param   string key  - the key to access
 * @param   mixed value - the value
 * @return  1| throw
 */
static int set_value(string|int key, mixed value) 
{
    string tbl = "mi_"+sDbTable;
    string qkey = "'"+fDb()->quote_index((string)key)+"'";
    string qval = "'"+fDb()->quote_index((string)serialize(value))+"'";
    

    if( sizeof(fDb()->query("SELECT k FROM %s WHERE v=%s", tbl, qval)) )
	fDb()->big_query("UPDATE %s SET k=%s WHERE v=%s", tbl, qkey, qval);
    else
	fDb()->big_query("INSERT INTO %s VALUES (%s, %s)", tbl, qkey, qval);
    return 1;
}

/**
 * delete all entries associated to a key, or a key value pair from the
 * database.
 * @param   string|int key
 * @param   string|int|void value
 * @result  int - Number of deleted entries
 */
static int delete(string|int|void key, mixed|void value) {
    string svalue;

    if (!intp(key) && !stringp(key) &&
        !intp(value) && !stringp(value) && !objectp(value))
        return 0;
    if (stringp(value) || intp(value))
        svalue = serialize(value);
    fDb()->big_query("delete from mi_"+ sDbTable+" where "+
                     ((stringp(key) || intp(key)) ? "k = '" + key + "'" +
                      ((stringp(value) || intp(value)) ? "and v = '" +
                       svalue + "'" : "") : "v = '" + svalue + "'"));
    return 1;
}
/**
 * delete all entries associated to a key, or a key value pair from the
 * database.
 * @param   string|int key
 * @param   string|int|void value
 * @result  int - Number of deleted entries
 */
static int delete_value(mixed value) {
    string svalue = serialize(value);
    fDb()->big_query("delete from mi_"+ sDbTable+
                     " where v = '" + svalue + "'");
    return fDb()->master_sql->affected_rows();
}

/**
 * give a list of all indices (keys) of the database table
 * @param   none
 * @return  an array containing the keys
 * @see     maapping.indices
 */
static array(string) index() {
    Sql.sql_result res =
	fDb()->big_query("select k from mi_"+sDbTable);
    int sz = res->num_rows();
    array(string) sIndices = allocate(sz);
    int i;
    for(i=0; i<sz; i++)
	sIndices[i] = res->fetch_row()[0];
    return sIndices;
}

