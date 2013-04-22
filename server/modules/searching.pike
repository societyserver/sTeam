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
 * $Id: searching.pike,v 1.9 2010/02/01 23:35:23 nicke Exp $
 */
inherit "/kernel/db_searching";

#include <database.h>
#include <macros.h>
#include <attributes.h>
#include <classes.h>
#include <access.h>

string get_identifier() { return "searching"; }

#define DEBUG_QUERY 1

#ifdef DEBUG_QUERY
#define LOG_QUERY(a, b...) werror(a,b);
#else
#define LOG_QUERY(a, b...)
#endif

static int searches = 0;
static object service;

class SearchToken {
  string storage;
  string query;
  string andor;
  string key;
  mixed value;
  
  void create(string store, string k, mixed v, string ao) {
    storage = store;
    key = k;
    if ( objectp(v) ) { 
      value = "%" + v->get_object_id();
    }
    value = v;
    andor = ao;
  }
  mapping get() {
    return ([ 
      "storage": storage,
      "key": key,
      "value": value,
    ]);
  }
}

string compose_value_expression(SearchToken st)
{
  string query;
  if ( st->storage == STORE_ATTRIB ) 
    query = " (ob_ident = 'attrib' and ob_attr='"+st->key+"' and ob_data "+
      st->value[0]+" '"+st->value[1]+"') ";
  else if ( st->storage == "doc_data" ) 
    query = " (match(doc_data) against (\""+st->value[1]+"\") ";
  else
    query = " (ob_data "+ st->value[0]+" '" + st->value[1]+"') ";
  return query;
}

string compose_value_expressions(array tokens)
{
  string query = "";

  SearchToken last = tokens[0];
  string exp = compose_value_expression(last);

  for ( int i = 1; i < sizeof(tokens); i++ ) {
    SearchToken token = tokens[i];
    query += exp + " or ";
    exp = compose_value_expression(token);
  }
  query += exp;
  
  return query;
}

string get_table_name() { return "ob_data"; }

class Result {
  
  function f;
  mixed args;
  void create(function func, mixed a) { f = func; args = a; }

  void asyncResult(mixed id, mixed result) {
    f(args, result);
  }
}

static mapping results = ([ ]);

class Search {

  array eq(string|int value) {
    return ({ "=",
	      intp(value) ? (string)value : fDb()->quote(value)
    });
  }
  array gt(string|int value) {
    return ({ ">", intp(value) ? (string)value : fDb()->quote(value)});
  }
  array lt(string|int value) {
    return ({ "<", intp(value) ? (string)value : fDb()->quote(value)});
  }
  array like(string value) {
    return ({ "like", intp(value) ? (string)value : fDb()->quote(value)});
  }
  array lte(string|int value) {
    return ({ "<=", intp(value) ? (string)value : fDb()->quote(value)});
  }
  array gte(string|int value) {
    return ({ ">=", intp(value) ? (string)value : fDb()->quote(value)});
  }
  array btw(string|int low, string|int up) {
    return and(gte(low), lte(up));
  }
  array or(array a, array b) {
    return ({ "or", ({a, b}) });
  }
  array and(array a, array b) {
    return ({ "and", ({a, b}) });
  }

  array extends = ({ });  
  array limits = ({ });
  array fulltext = ({ });
  array(string) classes;
  int search_id;
  
  void create(int sid, array cl) {
    classes = cl;
    search_id = sid;
    service = get_module("ServiceManager");
  }

  void search_attribute(string key, string value) {
    extends += ({ search(STORE_ATTRIB, key, like(value), "or") });
  }

  void first_query(string store, string key, mixed value, mixed filter) {
    extends += ({ search(store, key, value, "or") });
  }

  void limit(string store, string key, mixed value) {
    limits += ({ search(store, key, value, "and") });
  }
  void extend(string store, string key, mixed value) {
    extends += ({ search(store, key, value, "or") });
  }
  
  void extend_ft(string pattern) {
    fulltext += ({ SearchToken("doc_ft", "doc_data", pattern, "or") });
  }
 
  SearchToken search(string store, string key, mixed value, string andor) {
    return SearchToken(store, key, value, andor);
  }
  mapping serialize_token(SearchToken s) {
    return s->get();
  }
  void execute() { run(); }
  void run() {
    if ( !service->is_service("search") ) {
      FATAL("Unable to locate Search Service - running locally !");
      string _query = "select distinct ob_id from ( ob_data ";
      
      if ( arrayp(classes) && sizeof(classes) > 0 ) {
	_query += "INNER JOIN ob_class on ob_class.ob_id=ob_data.ob_id and ("+
	  ( "ob_class = "+classes*" or ob_class=")+")";
      }
      _query += ") where";
      
      
      _query += compose_value_expressions(extends);
      LOG_QUERY("Query is: %s", _query);
      array res = query(_query);
      array sresult = ({ });
      foreach(res, mixed r) 
	if ( mappingp(r) )
	  sresult += ({ r->ob_id });
      
      handle_service(search_id, sresult);
    }
    else {
	object result = 
	  service->call_service_async("search", 
		   ([ "this": this(),
		      "search_id": search_id,
		      "classes": classes,
		      "extends": map(extends, serialize_token),
		      "limits": map(limits, serialize_token),
		      "fulltext": map(fulltext, serialize_token), ]));

	// process result;
	result->vars = ([ "id": search_id, ]);
	result->processFunc = handle_result;
	result->resultFunc = results[search_id]->asyncResult;
    }
  }
  object run_async() {
      if ( !service->is_service("search") )
	  steam_error("Unable to locate search service !");
      return
	service->call_service_async("search", 
		   ([ "this": this(),
		      "search_id": search_id,
		      "classes": classes,
		      "extends": map(extends, serialize_token),
		      "limits": map(limits, serialize_token),
		      "fulltext": map(fulltext, serialize_token), ]));
  }
}

array handle_result(array res)
{
  int size = sizeof(res);
  array result = ({ });

  for (int i =0; i<size; i++) {
    object o = find_object((int)res[i]);
    if ( objectp(o) && o->status() >= 0 )
      result += ({ o });
  }
  return result;
}

void handle_service(int id, array result) 
{
  result = handle_result(result);
  Result r = results[id];
  r->f(r->args, result);
}

Search searchQuery(function result_cb, mixed result_args, mixed ... params)
{
  results[++searches] = Result(result_cb, result_args);
  return Search(searches, @params);
}

object searchAsyncAttribute(string key, mixed val, mixed ... params) 
{
  Async.Return r = Async.Return();
  results[++searches] = Result(r->asyncResult, 0);
  Search s = Search(searches, @params);
  s->search_attribute(key, val);
  s->run();
  return r;
}
  
object searchAsync(array extends, array limits, array fulltext, void|int cBits)
{
  array classlist = ({ });
  int i = (1<<0);
  while ( (cBits > 0) && (i < (1<<31)) )
  {
    if ( (cBits & i) == cBits)
      classlist += ({ _Database->get_class_string(i) });
    i = i << 1;
  }
  object aResult = get_module("ServiceManager")->call_service_async("search", 
				     ([ "this": this(), 
					"search_id": searches, 
					"classes": classlist,
					"extends": extends, 
					"limits": limits, 
					"fulltext": fulltext, ]));
  aResult->processFunc = handle_result;
  return aResult;
}

array(object) search_simple(string searchTerm, void|int classBit)
{
  object handle = _Database->get_db_handle();
  string query = "SELECT distinct ob_id from ob_class WHERE obkeywords";
  if (search(searchTerm, "%") >= 0)
    query += " like '"+ handle->quote(searchTerm) + "'";
  else
    query += "='"+handle->quote(searchTerm) +"'";

  if (classBit) 
    query += " AND ob_class='"+_Database->get_class_string(classBit)+"'";
  object result = handle->big_query(query);
  array resultArr = allocate(result->num_rows());
  for (int i=0; i < result->num_rows(); i++) {
    mixed row = result->fetch_row();
    resultArr[i] = find_object((int)row[0]);
  }
  return resultArr;
}

string object_to_dc(object obj) 
{
  string rdf = "<rdf:RDF\n"+
  "xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"\n"+
  "xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n";
  
  object creator = obj->get_creator() || USER("root");
  
  rdf += sprintf("<rdf:Description rdf:about=\"%s\">\n"+
		 "<dc:creator>%s</dc:creator>\n"+
		 "<dc:title>%s</dc:title>\n"+
		 "<dc:description>%s</dc:description>\n"+
		 "<dc:subject>%s</dc:subject>\n"+
		 "<dc:source>%s</dc:source>\n"+
		 "<dc:date>%s</dc:date>\n"+
		 "<dc:type>%s</dc:type>\n"+
		 "<dc:identifier>%s</dc:identifier>\n"+
		 "</rdf:Description>\n",
		 get_module("filepath:tree")->object_to_filename(obj),
		 creator->get_name(),
		 obj->get_identifier(),
		 obj->query_attribute(OBJ_DESC),
		 "",
		 "",
		 (string)obj->query_attribute(OBJ_CREATION_TIME),
		 obj->query_attribute(DOC_MIME_TYPE) || "",
		 (string)obj->get_object_id()
		 );
  return rdf; 
}

object searchKeyword(string keyword) 
{
  object aResult = get_module("ServiceManager")->call_service_async(
					 "search", 
					 ([ "this": this(), 
					    "search_id": searches, 
					    "classes": ({ }), 
					    "extends": (["keyword": keyword]),
					    "limits": ({ }),
					    "fulltext": ({ }), ]));
  aResult->processFunc = handle_result;
  return aResult;
}



/**
 * Filters an array of objects and returns those objects matching specified
 * filter rules, sorted in a specified order and with optional pagination.
 *
 * The filter entries are applied in the order in which they are given. Each
 * filter must be an array like this:
 *   ({ +/-, "class", class-bitmask })
 *   ({ +/-, "attribute", attribute-name, condition, value/values })
 *   ({ +/-, "function", function-name, condition, value/values, [params] })
 *   ({ +/-, "access", access-bitmask })
 * If an object doesn't match any filter rule, it will be excluded by
 * default, so if you would like to include any objects that didn't match any
 * filter, append ({ "+", "class", CLASS_ALL }) to the end of your filter list.
 * If the second parameter of a filter is prefixed by an exclamation mark, then
 * the filter rule will match if the condition is not met. E.g.:
 *   ({ -, "!access", access-bitmask })
 *
 * * +/- must be either "+" (include) or "-" (exclude) as a string.
 * * class-bitmask must be either a CLASS_* constant or a combination (binary
 *   OR) of CLASS_* constants (e.g. CLASS_CONTAINER|CLASS_DOCUMENT).
 * * attribute-name must be the name (key) of an attribute, e.g. "OBJ_NAME".
 * * condition must be one of the following strings: "==", "!=", "<",
 *   "<=", ">", ">=", "prefix", "suffix". Note that some conditions will only
 *   match for certain attribute types, e.g. int, float or string.
 * * value/values must be either a simple value like int, float, string,
 *   object, or an array of simple values, in which case the condition will
 *   try to match at least one of these values.
 * * params is optional and must be an array of parameters to pass to the
 *   function if specified.
 * * access-bitmask must be either a SANCTION_* constant or a combination
 *   (binary OR) of SANCTION_* constants (e.g. SANCTION_READ|SANCTION_ANNOTATE).
 *
 * The sort entries are applied in the order in which they are given in case
 * some entries are considered equal regarding the previous sort rule. Each
 * sort entry must be an array like this:
 * ({ >/<, "class", class-order })
 * ({ >/<, "attribute", attribute-name })
 *
 * * >/< must be "<" (ascending) or ">" (descending)
 * * class-order is optional and can be an array of CLASS_* constants. The
 *   result will be sorted in the specified order by the objects that match
 *   the specified classes. All classes that were not specified will be
 *   considered equal for this sort entry.
 * * attribute-name must be the name (key) of an attribute, e.g. "OBJ_NAME".
 *
 * Example:
 * Return all documents and containers (no users) that the user can read,
 * sorted by type and then
 * name:
 * filter_objects_array(
 *   ({  // filters:
 *     ({ "-", "!access", SANCTION_READ }),
 *     ({ "-", "class", CLASS_USER }),
 *     ({ "+", "class", CLASS_DOCUMENT|CLASS_CONTAINER })
 *   }),
 *   ({  // sort:
 *     ({ "<", "class", ({ CLASS_CONTAINER, CLASS_DOCUMENT }) }),
 *     ({ "<", "attribute", "OBJ_NAME" })
 *   }) );
 *
 * Example:
 * Return all documents with keywords "urgent" or "important" that the user
 * has read access to, that are no wikis and that have been changed in the
 * last 24 hours, sort them by modification date (newest first) and return
 * only the first 10 results:
 * filter_objects_array(
 *   ({  // filters:
 *     ({ "-", "!access", SANCTION_READ }),
 *     ({ "-", "attribute", "OBJ_TYPE", "prefix", "container_wiki" }),
 *     ({ "-", "attribute", "DOC_LAST_MODIFIED", "<", time()-86400 }),
 *     ({ "-", "attribute", "OBJ_KEYWORDS", "!=", ({ "urgent", "important" }) }),
 *     ({ "+", "class", CLASS_DOCUMENT })
 *   }),
 *   ({  // sort:
 *     ({ ">", "attribute", "DOC_LAST_MODIFIED" })
 *   }), 0, 10 );
 *
 * @param objects the array of which to retrieve a filtered selection
 * @param filters (optional) an array of filters (each an array as described
 *   above) that specify which objects to return
 * @param sort (optional) an array of sort entries (each an array as described
 *   above) that specify the order of the items (before pagination)
 * @param offset (optional) only return the objects starting at (and including)
 *   this index
 * @param length (optional) only return a maximum of this many objects
 * @return a mapping ([ "objects":({...}), "total":nr, "length":nr,
 *   "start":nr, "page":nr ]), where the "objects" value is an array of
 *   objects that match the specified filters, sort order and pagination.
 *   The other indices contain pagination information ("total" is the total
 *   number of objects after filtering but before applying "length", "length"
 *   is the requested number of items to return (as in the parameter list),
 *   "start" is the start index of the result in the total number of objects,
 *   and "page" is the page number (starting with 1) of pages with "length"
 *   objects each, or 0 if invalid).
 */
mapping paginate_object_array ( array objects, array|void filters, array|void sort, int|void offset, int|void length )
{
  array(object) result;
  if ( !arrayp(filters) || sizeof(filters) == 0 )
    result = objects;
  else {
    // filter objects:
    result = ({ });
    foreach ( objects, object obj ) {
      if ( !objectp(obj) ) continue;
      foreach ( filters, mixed filter ) {
        if ( !arrayp(filter) || sizeof(filter) < 2 )
          THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
        int done;
        int invert = 0;
        string filter_type = filter[1];
        if ( has_prefix( filter_type, "!" ) ) {
          invert = 1;
          filter_type = filter_type[1..];
        }
        switch ( filter_type ) {
          
          case "class":
            if ( sizeof(filter) < 3 )
              THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
            int obj_class = obj->get_object_class();
            if ( invert != ((filter[2] & obj_class) != 0) ) {  // matches class
              if ( filter[0] == "+" ) {  // include class
                result += ({ obj });
                done = 1;
              }
              else done = 1;  // exclude class
            }
            break;  // class

          case "access": {
            if ( sizeof(filter) < 3 )
              THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
            if ( invert != (get_module( "security" )->check_user_access( obj,
                                 this_user(), filter[2], 0, false ) != 0) ) {
              if ( filter[0] == "+" ) { // include
                result += ({ obj });
                done = 1;
              }
              else done = 1;  // exclude
            }
          } break;  // access
          
          case "attribute":
          case "function":
            if ( sizeof(filter) < 5 )
              THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
            mixed value;
            if ( filter_type == "function" ) {
              mixed func_name = filter[2];
              if ( sizeof(filter) > 5 ) {
                mixed func_params = filter[5];
                if ( !arrayp(func_params) ) func_params = ({ func_params });
                catch( value = obj->find_function(func_name)( @func_params ) );
              }
              else {
                catch( value = obj->find_function(func_name)() );
              }
            }
            else
              value = obj->query_attribute( filter[2] );
            if ( mappingp(value) )
              break; // ignore mappings
            mixed target_value = filter[4];
            switch ( filter[3] ) {  // condition:
              case "==":
                if ( !arrayp(value) ) {
                  if ( invert != (value == target_value) ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( subvalue == target_value ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // ==
              case "!=":
                if ( !arrayp(value) ) {
                  if ( invert != (value != target_value) ) done = 1;
                  break;
                }
                int found_equal = 0;
                foreach ( value, mixed subvalue ) {
                  if ( subvalue == target_value ) {
                    found_equal = 1;
                    break;
                  }
                }
                done = !found_equal;
                if ( invert ) done = !done;
                break;  // !=
              case "<=":
                if ( !arrayp(value) ) {
                  if ( invert != (value <= target_value) ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( subvalue <= target_value ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // <=
              case ">=":
                if ( !arrayp(value) ) {
                  if ( invert != (value >= target_value) ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( subvalue >= target_value ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // >=
              case "<":
                if ( !arrayp(value) ) {
                  if ( invert != (value < target_value) ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( subvalue < target_value ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // <
              case ">":
                if ( !arrayp(value) ) {
                  if ( invert != (value > target_value) ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( subvalue > target_value ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // >
              case "prefix":
                if ( stringp(value) ) {
                  if ( invert != has_prefix( value, target_value ) ) done = 1;
                  break;
                }
                if ( !arrayp(value) ) {
                  if ( invert ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( !stringp(subvalue) ) continue;
                  if ( invert != has_prefix( subvalue, target_value ) ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // prefix
              case "suffix":
                if ( stringp(value) ) {
                  if ( invert != has_suffix( value, target_value ) ) done = 1;
                  break;
                }
                if ( !arrayp(value) ) {
                  if ( invert ) done = 1;
                  break;
                }
                foreach ( value, mixed subvalue ) {
                  if ( !stringp(subvalue) ) continue;
                  if ( has_suffix( subvalue, target_value ) ) {
                    done = 1;
                    break;
                  }
                }
                if ( invert ) done = !done;
                break;  // suffix
            }
            if ( done && filter[0] == "+" ) {  // condition matches
              result += ({ obj });
            }  // otherwise "done" is set and the object will be excluded
            break;  // attribute
            
        }
        if ( done ) break;
      }  // foreach filters
    }  // foreach objects
  }  // if has filters

  // sort result:
  if ( arrayp(sort) && sizeof(sort) > 0 ) {
    result = Array.sort_array( result, sort_objects_filter, sort );
  }
  
  mapping info = ([ "total":sizeof(result), "length":length, "start":offset,
                    "page":0, "objects":({ }) ]);
  if ( offset >= sizeof(result) ) return info;
  if ( offset != 0 || ( length > 0 && length < sizeof(result) ) ) {
    if ( length < 1 || (offset + length >= sizeof(result)) )
      length = sizeof(result) - offset;
    result = result[ offset .. (offset+length-1) ];
  }
  if ( result == objects )
    result = copy_value( objects );
  info["objects"] = result;
  info["page"] = (int)ceil( (float)length / (float)info["total"] );
  return info;
}

/**
 * Filters an object array according to filter rules, sorting, offset and
 * length. This returns the same as the "objects" index in the result of
 * paginate_object_array() and is here for compatibility reasons and ease of
 * use (if you don't need pagination information).
 *
 * @see paginate_object_array
 */
array filter_object_array ( array objects, array|void filters, array|void sort, int|void offset, int|void length )
{
  return paginate_object_array( objects, filters, sort, offset, length )["objects"];
}

object paginate_search_async ( array|void filters, array|void sort, int|void offset, int|void length )
{
  array limits = ({ });
  array extends = ({ });
  array fulltext = ({ });
  int classes;
  int classes_not;
  array remaining_filters = ({ });

  foreach ( filters, mixed filter ) {
    if ( !arrayp(filter) || sizeof(filter) < 2 )
      THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
    int invert = 0;
    string filter_type = filter[1];
    if ( has_prefix( filter_type, "!" ) ) {
      // inverted filters are currently not handled in the search itself,
      // they will be applied after the search.
      remaining_filters += ({ filter });
      continue;
    }

    switch ( filter_type ) {
      
    case "class":
      if ( sizeof(filter) < 3 )
        THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
      if ( filter[0] == "+" ) classes |= filter[2];
      else classes_not |= filter[2];
      break;

    case "access":
      if ( sizeof(filter) < 3 )
        THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
      // access filters are currently applied after the search, they are not
      // handled by the search itself
      remaining_filters += ({ filter });
      continue;
      break;

    case "function":
      if ( sizeof(filter) < 5 )
        THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
      // functions are currently not handled by the search itself, these
      // filters will be applied after the search
      remaining_filters += ({ filter });
      continue;
      break;

    case "attribute":
      if ( sizeof(filter) < 5 )
        THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
      string attrib = filter[2];
      string condition = filter[3];
      mixed target_value = filter[4];
      switch ( condition ) {
        case "==":
          condition = "=";
          break;
        case "<":
        case ">":
        case "<=":
        case ">=":
        case "!=":
        case "like":
          // condition is okay for search
          break;
        case "prefix":
        case "suffix":
          condition = "like";
          // like doesn't check strictly enough, so use it for a first
          // selection and then run the filter after the search
          remaining_filters += ({ filter });
          break;
        default:
          THROW( "Invalid condition for search: " + condition, E_ERROR );
      }
      if ( !arrayp( target_value ) ) target_value = ({ target_value });
      foreach ( target_value, mixed value ) {
        if ( filter[0] == "+" ) extends += ({ ([ "storage":"attrib",
                "key":attrib, "value":({ condition, value }) ]) });
        else limits += ({ ([ "storage":"attrib",
                "key":attrib, "value":({ condition, value }) ]) });
      }
      break;

      case "content":
        if ( sizeof(filter) < 3 )
          THROW( sprintf( "Invalid filter: %O", filter ), E_ERROR );
        // limiting by content is not supported at the moment:
        if ( filter[0] != "+" ) break;
        fulltext += ({ ([ "storage":"doc_ft", "value":filter[2] ]) });
        break;
    }
  }

  if ( classes == 0 ) classes = CLASS_ALL & (~classes_not);
  array classlist = ({ });
  if ( classes != CLASS_ALL ) {
    int cBits = classes;
    while ( cBits ) {
      mixed class_string = _Database->get_class_string(cBits);
      if ( class_string != "/classes/Object" )
        classlist += ({ class_string });
      cBits = cBits >> 1;
    }
  }

  object async_result = get_module("ServiceManager")->call_service_async(
      "search", ([ "this":this(), "search_id":searches, "classes":classlist,
                   "extends":extends, "limits":limits, "fulltext":fulltext ])
  );
  async_result->processFunc = handle_paginate_search_result;
  async_result->userData = ([ "filters":remaining_filters, "sort":sort,
                              "offset":offset, "length":length ]);
  return async_result;
}

static mapping handle_paginate_search_result ( array res, mapping data )
{
  array objects = ({ });
  foreach ( res, mixed obj ) {
    if ( stringp(obj) ) obj = (int)obj;
    if ( intp(obj) ) obj = find_object( obj );
    if ( objectp(obj) ) objects += ({ obj });
  }
  return paginate_object_array( objects, data->filters, data->sort,
                                data->offset, data->length );
}

object filter_search_async ( array|void filters, array|void sort, int|void offset, int|void length )
{
  object async_result = paginate_search_async( filters, sort, offset, length );
  async_result->processFunc = handle_filter_search_result;
  return async_result;
}

static array handle_filter_search_result ( array res, mapping data )
{
  array objects = ({ });
  foreach ( res, mixed obj ) {
    if ( stringp(obj) ) obj = (int)obj;
    if ( intp(obj) ) obj = find_object( obj );
    if ( objectp(obj) ) objects += ({ obj });
  }
  return filter_object_array( objects, data->filters, data->sort,
                              data->offset, data->length );
}

static int sort_objects_filter ( object obj1, object obj2, array rules )
{
  foreach ( rules, array rule ) {
    int reverse = 0;
    if ( rule[0] == ">" ) reverse = 1;
    switch ( rule[1] ) {
      case "class":
        int obj_class1 = obj1->get_object_class();
        int obj_class2 = obj2->get_object_class();
        if ( sizeof(rule) < 3 ) {
          if ( obj_class1 > obj_class2 ) return 1 ^ reverse;
          else if ( obj_class1 < obj_class2 ) return 0 ^ reverse;
          continue;
        }
        int index1 = -1;
        int index2 = -1;
        int index = 0;
        foreach ( rule[2], int obj_class ) {
          if ( obj_class & obj_class1 ) index1 = index;
          if ( obj_class & obj_class2 ) index2 = index;
          if ( index1 >= 0 && index2 >= 0 ) break;
          index++;
        }
        if ( index1 > index2 ) return 1 ^ reverse;
        else if ( index1 < index2 ) return 0 ^ reverse;
        break;

      case "attribute":
        mixed value1;
        mixed value2;
        if ( arrayp( rule[2] ) ) {
          foreach ( rule[2], mixed key ) {
            if ( !value1 ) value1 = obj1->query_attribute( key );
            if ( !value2 ) value2 = obj2->query_attribute( key );
          }
        }
        else {
          value1 = obj1->query_attribute( rule[2] );
          value2 = obj2->query_attribute( rule[2] );
        }
        if ( value1 == 0 && value2 == 0 ) continue;
        if ( stringp(value1) && value2 == 0 ) return 1 ^ reverse;
        else if ( value1 == 0 && stringp(value2) ) return 0 ^ reverse;
        else if ( stringp(value1) && stringp(value2) ) {
          if ( value1 > value2 ) return 1 ^ reverse;
          else if ( value1 < value2 ) return 0 ^ reverse;
          else break;
        }
        else if ( (intp(value1) || floatp(value1)) &&
                  (intp(value2) || floatp(value2)) ) {
          if ( value1 > value2 ) return 1 ^ reverse;
          else if ( value1 < value2 ) return 0 ^ reverse;
          else break;
        }
        break;
    }
  }
  return 0;
}



private static array test_objects = ({ });

void test()
{
  // first create some objects to search
  object obj = get_factory(CLASS_DOCUMENT)->execute((["name": "document.doc", ]));
  obj->set_attribute(OBJ_KEYWORDS, ({ "Mistel", "approach" }));
  test_objects += ({ obj });
  // test external search service
  Test.add_test_function(test_search, 20, 1, ([ ]));
}

void test_cleanup()
{
  if ( arrayp(test_objects) ) {
    foreach ( test_objects, object obj )
      catch ( obj->delete() );
  }
}

void search_test_finished(object result, array results)
{
  if ( sizeof(results) == 0 ) {
    Test.failed(result->userData->name,
		"Search %s finished with %d results in %d ms", 
		result->userData->name,
		sizeof(results), 
		get_time_millis()-result->userData->time);
  }
  else {
    Test.succeeded(result->userData->name,
		   "Search %s finished with %d results in %d ms", 
		   result->userData->name,
		   sizeof(results), 
		   get_time_millis()-result->userData->time);
  }
  result->userData->tests[result->userData->name] = 1;
}

static void test_search(int nr_tries, mapping tests)
{
  object serviceManager = get_module("ServiceManager");

  if ( !Test.test("Service Manager", 
		  objectp(serviceManager), "Failed to find ServiceManager!") )
    return;
  
  if ( !serviceManager->is_service("search") ) {
    if ( nr_tries > 20 )
      Test.failed("search service", 
		  "failed to locate search services after %d tries",
		  nr_tries);
    else
      Test.add_test_function(test_search, 10, nr_tries+1, tests);
    return;
  }
  if ( sizeof(tests) != 0 ) {
    foreach(values(tests), int i) {
      if ( i == 0 ) {
	werror("Waiting for tests to finish!");
	Test.add_test_function(test_search, 10, nr_tries+1, tests);
      }
    }
    return;
  }

  // now search for common queries
  object result, query;

  // a single search
  tests["simple1"] = 0;
  query = searchQuery(search_test_finished, ([ ]),  ({ }));
  query->extend(STORE_ATTRIB, OBJ_NAME, query->like("steam"));
  result = query->run_async();
  result->resultFunc = search_test_finished;
  result->userData = ([ "name": "simple1", 
			"tests":tests, 
			"time":get_time_millis(),]);

  tests["simple2"] = 0;
  query = searchQuery(search_test_finished, ([ ]),  ({ }));
  query->extend(STORE_ATTRIB, OBJ_NAME, query->like("steam"));
  query->extend(STORE_ATTRIB, OBJ_DESC, query->like("steam"));
  query->extend(STORE_ATTRIB, OBJ_KEYWORDS, query->like("steam"));
  result = query->run_async();
  result->resultFunc = search_test_finished;
  result->userData = ([ "name": "simple2", 
			"tests":tests, 
			"time":get_time_millis(),]);


  tests["keywords"] = 0;
  query = searchQuery(search_test_finished, ([ ]),  ({ }));
  query->extend(STORE_ATTRIB, OBJ_KEYWORDS, query->like("Mistel"));
  result = query->run_async();
  result->resultFunc = search_test_finished;
  result->userData = ([ "name": "keywords", 
			"tests":tests, 
			"time":get_time_millis(),]);

  tests["target room"] = 0;
  query = searchQuery(search_test_finished, ([ ]),  ({ "\"/classes/Room\"" }));
  query->extend(STORE_ATTRIB, OBJ_NAME, query->like("coder%"));
  result = query->run_async();
  result->resultFunc = search_test_finished;
  result->userData = ([ "name": "target room", 
			"tests":tests, 
			"time":get_time_millis(),]);

  tests["user 1"] = 0;
  query = searchQuery(search_test_finished, ([ ]),  ({ "\"/classes/User\"" }));
  query->extend(STORE_ATTRIB, OBJ_NAME, query->like("service"));
  result = query->run_async();
  result->resultFunc = search_test_finished;
  result->userData = ([ "name": "user 1", 
			"tests":tests, 
			"time":get_time_millis(),]);

  Test.add_test_function(test_search, 10, 0, tests);
}
