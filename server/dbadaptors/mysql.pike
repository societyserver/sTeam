inherit "handle";

#include <macros.h>
#include <database.h>
#include <classes.h>
#include <attributes.h>

string describe() { return "MySQLHandle"; }

void check_tables()  
{
  string query;
  
  array tableinfo = oHandle->list_fields("ob_class", "obkeywords");
  // keywords update
  if ( sizeof(tableinfo) == 0 ) {
    query = "alter table ob_class add (obkeywords text, obname text, obdescription text, obmimetype text, obversionof text)";
    mixed err = catch(oHandle->big_query(query));
    if ( err != 0 ) {
      throw(err);
    }
  }
  tableinfo = oHandle->list_fields("ob_class", "obdecoration");
  if ( sizeof(tableinfo)==0 ) {
    query = "alter table ob_class add (obdecoration text)";
    oHandle->big_query(query);
    MESSAGE("Modified Table ob_class with decoration column!");
  }
}

int enable_decorations()
{
  array tableinfo = oHandle->list_fields("ob_class", "obdecoration");
  if ( sizeof(tableinfo)==0 ) 
    return 0;
  return 1;
}


mapping check_updates(object dbupdates, function update_classtableobject)
{
  mixed err;
  mapping resultmap = ([ ]);
  
  object update = dbupdates->get_object_byname("classIndex");
  if ( !objectp(update) ) {
    string query = "create index class on ob_class (ob_class)";
    catch(oHandle->big_query(query));
    query = "create fulltext index obkeywords on ob_class (obkeywords)";
    err=catch(oHandle->big_query(query));
    resultmap->classIndex = "Successfully created index class on ob_class !\n";

    if ( err != 0 ) {
      FATAL("Database: Class-Update Failed:\n%O\n%O", err[0], err[1]);
      resultmap->classIndex = sprintf("Failed:\n%O\n%O", err[0], err[1]);
    }

  }
  update = dbupdates->get_object_byname("classKeywords");
  if ( !objectp(update) ) {
    int ts = time();
    object res = oHandle->big_query("select ob_id from ob_class where ob_class !='-'");
    int sz = res->num_rows();
    MESSAGE("Updating Objects in class table .... "+
            "(might take a while: %d objects, ~%d minutes).....:\n ", 
            sz,
            sz/4800);
    for ( int i = 0; i < sz; i++ ) {
      int oid = (int)res->fetch_row()[0];
      update_classtableobject(oid);
      if ( i%1000 == 0 )
        write("#");
    }
    MESSAGE("** %d Objects updated in %d Seconds !", sz, time()-ts);
    resultmap->classKeywords =
      "Successfully installed keywords on ob_class !\n";
  }
  update = dbupdates->get_object_byname("binaryContent");
  if ( !objectp(update) ) {
    object res = oHandle->big_query("select ob_id from ob_class where ob_class !='-'");
    int sz = res->num_rows();
    
    MESSAGE("Updating doc_data table - setting binary content blobs, ~%d minutes",
            sz/3600);
    int t = time();
    res = oHandle->big_query("alter table doc_data modify rec_data blob");
    resultmap->binaryContent = "Successfully updated CONTENT !\n";
    MESSAGE("Installed binary-content Update in database in %d seconds",
            time() - t);
  }

  object keywordUpdate = dbupdates->get_object_byname("keywords");
  if ( !objectp(keywordUpdate) ) {
    object attr = get_factory(CLASS_OBJECT)->describe_attribute(OBJ_KEYWORDS);
    attr->set_acquire(0);
    get_factory(CLASS_OBJECT)->register_attribute(attr);
    array tables = oHandle->list_tables();
    catch(oHandle->big_query("drop index obkeywords on ob_class"));
    if ( search(tables, "mi_keyword_index") != -1 ) {
      object res = oHandle->big_query("select k,v from mi_keyword_index");
      object tagmod = get_module("tagging");

      for ( int i = 0; i < res->num_rows(); i++ ) {
	int oid;
	object obj;
        string keyword;
	
	mixed erg = res->fetch_row();
	if ( sscanf(erg[1], "%%%d", oid) != 1 )
	  continue;
        if ( sscanf(erg[0], "\"%s\"", keyword) != 1 )
          keyword = erg[0];
	
	obj = find_object(oid);
	if ( !objectp(obj) )
	  continue;
	if ( objectp(tagmod) )
	  tagmod->tag_object(obj, keyword);
      }
      catch(oHandle->big_query("drop table mi_keyword_index"));
      
      MESSAGE("Converted " + res->num_rows() + " keywords");
    }
    mixed err = catch(oHandle->big_query("create fulltext index obkeywords on ob_class (obkeywords)"));
    
    keywordUpdate = get_factory(CLASS_DOCUMENT)->execute((["name":"keywords"]));
    keywordUpdate->set_content("Updated documents and acquire for OBJ_KEYWORDS!"+
			       (err!=0?sprintf("%O\n%O\n",err[0],err[1]):""));
    keywordUpdate->move(dbupdates);
  }
  // userlookup index on login
  object userLookupUpdate = dbupdates->get_object_byname("userLookup");
  if ( !objectp(userLookupUpdate) ) {
    catch(oHandle->big_query("create index loginlookup on i_userlookup (login)"));
    catch(oHandle->big_query("create index emaillookup on i_userlookup (email)"));
    catch(oHandle->big_query("create index firstnamelookup on i_userlookup (firstname)"));
    catch(oHandle->big_query("create index lastnamelookup on i_userlookup (lastname)"));

    userLookupUpdate = get_factory(CLASS_DOCUMENT)->execute((["name":"userLookup"]));
    userLookupUpdate->set_content("Created indices on i_userlookup !");
    userLookupUpdate->move(dbupdates);
    
  }
  object securityCache = dbupdates->get_object_byname("securityCache");
  if ( !objectp(securityCache) ) {
    catch(oHandle->big_query("create index securityklookup on i_security_cache \
(k)"));
    catch(oHandle->big_query("create index securityvlookup on i_security_cache \
(v)"));
    securityCache = get_factory(CLASS_DOCUMENT)->execute((["name":"securityCach\
e"]));
    securityCache->set_content("Created index on security cache !");
    securityCache->move(dbupdates);
  }
  
  object obDataIndex = dbupdates->get_object_byname("obDataIndex");
  if ( !objectp(obDataIndex) ) {
    MESSAGE("Creating index on ob_data - could take a while depending on the size of your database!");
    catch(oHandle->big_query("create index obdatalookup on ob_data (ob_data(40))"));
    obDataIndex = get_factory(CLASS_DOCUMENT)->execute((["name":"obDataIndex"]));
    obDataIndex->set_content("Created index on ob_data");
    obDataIndex->move(dbupdates);
  }

  object binaryAttr = dbupdates->get_object_byname("Binary_Attributes");
  if (!objectp(binaryAttr)) {
    MESSAGE("Updating database (changing ob_data to use varchar(128) binary for ob_attr) - could take a while depending on the size of your database!");
    mixed err=catch(oHandle->big_query("alter table ob_data modify ob_attr varchar(128) binary"));
    if (err)
      MESSAGE("Error: %O\n%O", err[0], err[1]);
    else {
      binaryAttr = get_factory(CLASS_DOCUMENT)->execute((["name":"Binary_Attributes",]));
      binaryAttr->set_content("Collation on ob_data set to utf8_bin");
      binaryAttr->move(dbupdates);
    }
  }

  return resultmap;
}

void create_tables()
{
    MESSAGE("creating table \"doc_data\" ");
    oHandle->big_query("create table doc_data ("+
                      " rec_data text, "+
		      " doc_id int, "+
		      " rec_order int, "+
                      " primary key (doc_id, rec_order)"+
                      ") AVG_ROW_LENGTH=65535 MAX_ROWS=4294967296");
    //FIXME: postgres does not support (and probably not even need)
    //AVG_ROW_LENGTH and MAX_ROWS in this place
    
    
    MESSAGE("creating table \"ob_class\" ");
    oHandle->big_query("create table ob_class ("+
                      " ob_id int primary key, "+
                      " ob_class char(128) "+
                      ")");

    MESSAGE("creating table \"ob_data\" ");
    oHandle->big_query("create table ob_data ("+
                      " ob_id int, "+
                      " ob_ident char(15),"+
                      " ob_attr varchar(128) binary, "+
                      " ob_data mediumtext,"+
                      " unique(ob_id, ob_ident, ob_attr)"+
                      ")");
    MESSAGE("creating table \"variables\" ");
    oHandle->big_query("create table variables ("+
                      " var char(100) primary key, "+
                      " value int"+
                      ")");
}

