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
 * $Id: db_mapping.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 */

constant cvs_version="$Id: db_mapping.pike,v 1.2 2009/05/06 19:23:10 astra Exp $";


//! This class simulates a mapping inside the database.
//! Call get_value() and set_value() functions.

#include <macros.h>

private static string          sDbTable;
//private static mapping            mData;
private static function             fDb;

int get_object_id();

string tablename()
{
    return copy_value(sDbTable);
}

/**
 * connect a db_mapping with database.pike
 */
static final void load_db_mapping()
{
    // get database access function and tablename
    //    mData = ([]);
    [fDb , sDbTable]= _Database->connect_db_mapping();

    // we are in secure code, so create table according to
    // values from database.
    if( search(fDb()->list_tables(), "i_"+sDbTable ) == -1 )
    {
	fDb()->big_query("create table i_"+sDbTable+
			"(k char(255) not null, v text,"+
			 (fDb()->get_database() == "postgres" ?
			  "UNIQUE(k))":"UNIQUE(k, v(60)))"));
    }
}
    
/**
 * Index Operator for mapping emulation
 * @param   string key  - the key to access
 * @result  mixed value - the datastructure set with `[]= if any
 */
static mixed get_value(string|int key) {
    mixed row;

    //    if (d = mData[key])
    //	return d;

    //    LOG("db_mapping.get_value("+key+")");
    
    string query = "select v from i_"+sDbTable+
			 " where k = '"+fDb()->quote_index((string)key)+"'";
    Sql.sql_result res =
      fDb()->big_query(query);
    if (!objectp(res) ) {
      return 0;
    }
    else if ( !(row=res->fetch_row())) {
	destruct(res);
	return 0;
    }
    //    mData[key] = unserialize(row[0]);
    destruct(res);
    //    return mData[key];
    return unserialize(row[0]);
}

/**
 * all keys associated to a value.
 * @param   string value  - the value to access
 * @result  array keys    - a list (may be empty) of the keys denoting the val
 */
static array get_key(string|int|object value)
{
    mixed d = ({});
    mixed row;

    if (objectp(value) && !IS_PROXY(value))
        throw(({"Illeagal object given as value to get_key", backtrace()}));

    string svalue = serialize(value);
    //    LOG("search "+sDbTable +" for "+ (string) key);
    Sql.sql_result res =
	fDb()->big_query("select k from mi_"+sDbTable+
                         " where v like '"+ fDb()->quote_index(svalue) +"'");

    while (res && (row=res->fetch_row()))
        d+= ({ unserialize(row[0])});
    destruct(res);
    return d;
}
    
/**
 * Write Index Operator for mapping emulation
 * The serialization of the given value will be stored to the database
 * @param   string key  - the key to access
 * @param   mixed value - the value
 * @return  value| throw
 */
static mixed set_value(string|int key, mixed value) {
    //    mData[key]=value;
    //write("setting:"+serialize(value)+"\n");
     if(sizeof(fDb()->query("SELECT k FROM i_"+sDbTable+
                           " WHERE k='"+fDb()->quote_index((string)key)+"'")))
    {
      fDb()->big_query("UPDATE i_"+sDbTable+
                       " SET v='"+ fDb()->quote(serialize(value))+ "'"
                       " WHERE k='"+ fDb()->quote_index((string)key)+"'");
    }
    else
    {
      fDb()->big_query("INSERT INTO i_" + sDbTable +
		       " VALUES('" + fDb()->quote_index((string)key) + "', '" +
		       fDb()->quote(serialize(value)) + "')");
    }
    return value;
}

/**
 * delete a key from the database mapping emulation.
 * @param   string|int key
 * @result  int (0|1) - Number of deleted entries
 */
static int delete(string|int key) {
  fDb()->query("delete from i_"+ sDbTable+" where k = '"+
	       fDb()->quote_index(key)+"'");
  return 1;
}

/**
 * select keys from the database like the given expression.
 * @param   string|int keyexpression
 * @result  array(int|string)  
 */
static array report_delete(string|int key) {
    mixed aResult = ({});
    int i, sz;
    
    object handle = fDb();
    Sql.sql_result res = handle->big_query("select k from i_"+ sDbTable +
                         " where k like '"+ fDb()->quote_index(key)+"'");
    if (!res || !res->num_rows())
        return ({ });
          
    aResult = allocate(sz=res->num_rows());
    for (i=0;i<sz;i++)
        aResult[i] = res->fetch_row()[0];

    fDb()->big_query("delete from i_"+ sDbTable+" where k like '"+
		     fDb()->quote_index(key)+"'");
    //    m_delete(mData, (string) key);

    return aResult;
}

/**
 * give a list of all indices (keys) of the database table
 * @param   none
 * @return  an array containing the keys
 * @see     maapping.indices
 */
array(string) index()
{
    //    LOG("getting index()\n");
    
    Sql.sql_result res = fDb()->big_query("select k from i_"+sDbTable);
    //    LOG("done...");
#if 1
    int sz = res->num_rows();
    array(string) sIndices = allocate(sz);
    int i;
    for ( i = 0; i < sz; i++ )
    {
        string sres = copy_value(res->fetch_row()[0]);
	sIndices[i] = sres;
    }
#else
    array(string) sIndices = ({}); 
    array mres;
    while (mres = res->fetch_row())
        sIndices+=mres;
#endif
    destruct(res);
    return sIndices;
}

static void clear_table() 
{
  fDb()->big_query("delete from i_"+sDbTable+" where 1");
}

string get_table_name() { return (string)get_object_id(); }
