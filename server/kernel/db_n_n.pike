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
 * $Id: db_n_n.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: db_n_n.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";


#include <macros.h>

int get_object_id();

private static string          sDbTable;
private static function             fDb;

string tablename()
{
    return copy_value(sDbTable);
}

/**
 * connect a db_mapping with database.pike
 * @param  none
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
			  "unique (v, k))":"unique(v(60),k))"));
        //FIXME: postgres needs this as: 
        //(k char(255) not null unique,  v text unique)
    }
}
    
/**
 * get a list of all values associated with
 * @param   string key  - the key to access
 * @result  mixed value - the datastructure set with set_value
 * @see     set_value
 */
static mixed get_value(string|int|object key)
{
    mixed d = ({});
    mixed row;

    //    LOG_DEBUG("db_n_n.get_value "+sprintf("%O",key));
    if (objectp(key) && !IS_PROXY(key))
        throw(({"Illegal object given as key to get_value", backtrace()}));
    
    key = serialize(key);

    //    LOG_DB("search "+sDbTable +" for "+ (string) key);
    Sql.sql_result res =
        fDb()->big_query("select v from mi_"+sDbTable+
                         " where k like '"+fDb()->quote_index(key)+"'");

    while (res && (row=res->fetch_row()))
        d+= ({ unserialize(row[0])});
    destruct(res);
    return d;
}

/**
 * since the n_n module is symmetric, it might be interesting to retreive
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
                         " where v like '"+ fDb()->quote(svalue) +"'");

    while (res && (row=res->fetch_row()))
        d+= ({ unserialize(row[0])});
    destruct(res);
    return d;
}
    
/**
 * Add an entry into the list, there is no duplicate check
 * The serialization of the given value will be stored to the database
 * @param   array key  - the keys to store
 * @param   mixed value - the value to associate with the keys
 *                        if you pass an array to value, all of the keys given
 *                        will be registered for each of "values" members.
 * @return  1| throw
 */
static int set_value(mixed keys, mixed values)
{
    mixed key;
    mixed val;


    LOG_DEBUG("db_n_n.set_value:"+sprintf("%O",keys)+" "+sprintf("%O",values)+"\n");
    if (zero_type(keys) || zero_type(values))
        return 0;
    
    if (!arrayp(keys))
        keys = ({ keys });
    if (!arrayp(values))
        values = ({ values });

    delete_value(values);

    foreach(keys, key)
    {
        foreach(values, val)
        {
            //  LOG_DB("inserting "+master()->detailed_describe(value)+","+
            //         master()->detailed_describe(key));
            if(sizeof(fDb()->query("SELECT k FROM mi_"+sDbTable+" WHERE k='"
                                   +fDb()->quote(serialize(key))+"'")))
            {
              fDb()->big_query("UPDATE mi_"+sDbTable+ 
                               " SET v='"+ fDb()->quote(serialize(val))+"'"
                               " WHERE k='"+fDb()->quote(serialize(key))+"'");
            }
            else
            {
              fDb()->big_query("INSERT INTO mi_" + sDbTable +
                               " VALUES('" + fDb()->quote(serialize(key)) +
                               "', '" + fDb()->quote(serialize(val)) + "')");
            }
        }
    }
    return 1;
}

/**
 * delete all entries associated to a key, or a key value pair from the
 * database.
 * The NIL value below is defined in macros.h to create a zero_type
 * If used as an argument NIL matches all values. (use like an *)
 * @param   string|int|NIL  key
 * @param   string|int|void value
 * @result  int - Number of deleted entries
 */
static int delete(string|int|void|object key, string|int|void|object value)
{
    string svalue;

    if (zero_type(key) && zero_type(key))
        return 0;
    if (objectp(key) && (!IS_PROXY(key)))
        return 0;
    if (objectp(value) && (!IS_PROXY(value)))
        return 0;

    if (!zero_type(value))
        value = serialize(value);
    if (!zero_type(key))
        key = serialize(key);

    string bquery = "delete from mi_"+sDbTable+" where "+
        (!zero_type(key) ? "k = '" +fDb()->quote(key)+"'" :"") +
	(!zero_type(value) ? (!zero_type(key) ? "and " :"")+"v='" +svalue + "'" : "");

    fDb()->big_query(bquery);
    return 1;
}


/**
 * report_delete
 * same as delete, but also reports which elements got deleted
 * @param   string|int key
 * @param   string|int|void value
 * @result  array(string|int) keys of elements deleted
 */
static array(string|int|object)
report_deleted(string|int|object|void key, string|int|object|void value)
{
    string svalue;

        if (zero_type(key) && zero_type(key))
        return 0;

    if (objectp(key) && (!IS_PROXY(key)))
        return 0;
    if (objectp(value) && (!IS_PROXY(value)))
        return 0;

    if (!zero_type(value))
        value = serialize(value);
    if (!zero_type(key))
        key = serialize(key);

    string bquery = "mi_"+sDbTable+" where "+
        (!zero_type(key) ? "k = '" +fDb()->quote(key)+"'" :"") +
	(!zero_type(value) ? (!zero_type(key) ? "and " :"")+ "v='" +svalue + "'" : "");

    Sql.sql_result
        res = fDb()->big_query("select k from "+bquery);

    array tmp = ({});
    mixed row;
    while (res && (row=res->fetch_row()))
        tmp+= ({ unserialize(row[0]) });
    
    fDb()->big_query("delete from "+bquery);
    return tmp;
}

/**
 * delete all entries with a matching value
 * @param   string|int|object value
 * @result  int - Number of deleted entries
 * @see     delete with first Argument NIL
 */
static int delete_value(int|string|object value)
{

    if (objectp(value) && !IS_PROXY(value))
        throw(({"Illegal Object passed as value to delete_value", backtrace()}));

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
static array(string) index()
{
    Sql.sql_result res =
	fDb()->big_query("select k from mi_"+sDbTable);
    int sz = res->num_rows();
    array(string) sIndices = allocate(sz);
    int i;
    for(i=0; i<sz; i++)
	sIndices[i] = unserialize(res->fetch_row()[0]);
    return sIndices;
}

string get_table_name() { return (string)get_object_id(); }

