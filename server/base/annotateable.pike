/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: annotateable.pike,v 1.6 2008/04/15 14:14:44 exodusd Exp $
 */

constant cvs_version="$Id: annotateable.pike,v 1.6 2008/04/15 14:14:44 exodusd Exp $";

//! The annotation features of a sTeam object are implemented in this file.
//! Object uses it so any object inside a sTeam server features a list 
//! of annotations. The functions to add and remove annotations are located
//! in Object and call the low level functions in this class.

#include <macros.h>
#include <exception.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <roles.h>
#include <attributes.h>

static array(object) aoAnnotations; // list of annotations
static object           oAnnotates; // refering to ...

string        get_identifier();
void             update_path();
object                  this();
static void     require_save(void|string ident, void|string index);

/**
 * Initialization of annotations on this object.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see add_annotation
 * @see remove_annotation
 */
static void init_annotations()
{
    aoAnnotations = ({ });
    oAnnotates = 0;
}

/**
 * Add an annotation to this object. Any object can be an annotations, but
 * usually a document should be used here.
 *  
 * @param object ann - the documentation
 * @return if adding was successfull or not.
 * @see remove_annotation
 */
static bool add_annotation(object ann)
{
    if ( !IS_PROXY(ann) )
	THROW("Fatal error: annotation is not a proxy !", E_ERROR);
    LOG("Adding annotation: " + ann->get_object_id() + " on "+
	get_identifier());
    return do_add_annotation(ann);
}

static bool do_add_annotation(object ann)
{
    if ( objectp(ann->get_annotating() ) )
      steam_error("add_annotation: Annotation already on %d", 
                  ann->get_annotating()->get_object_id());
    aoAnnotations += ({ ann });
    
    ann->set_annotating(this());
    require_save(STORE_ANNOTS);
    return true;
}

/**
 * Remove an annotation from the object. The function just removes
 * the annotation from the list of annotations.
 *  
 * @param object ann - the annotation to delete
 * @return if removing was successfull.
 * @see add_annotation
 */
static bool remove_annotation(object ann)
{
    if ( !IS_PROXY(ann) )
	THROW("Fatal error: annotation is not a proxy !", E_ERROR);
    if ( search(aoAnnotations, ann) == -1 )
	THROW("Annotation not present at document !", E_ERROR);

    aoAnnotations -= ({ ann });
    ann->set_annotating(0);
    require_save(STORE_ANNOTS);
    return true;
}

/**
 * Remove all annotations. This will move the annotation to their
 * authors. The function is called when the object is deleted.
 *  
 */
static void remove_all_annotations() 
{
    mixed err;

    foreach( aoAnnotations, object ann ) {
	if ( objectp(ann) && ann->get_environment() == null ) {
	    object creator = ann->get_creator();
	    object trash = creator->query_attribute(USER_TRASHBIN);
	    err = catch {
		ann->delete();
	    };
            if ( err != 0 )
	    {
		FATAL("Failed to delete Annotation: %O", err);
	    }
	}
    }
    if ( objectp(oAnnotates) )
	catch(oAnnotates->remove_annotation(this()));
}

/**
 * This function returns a copied list of all annotations of this
 * object.
 *  
 * @return the array of annotations
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_annotations_for
 */
array(object) get_annotations(void|int from_obj, void|int to_obj)
{
    array annotations = ({ });

    if ( !arrayp(aoAnnotations) )
	aoAnnotations = ({ });

    aoAnnotations -= ({ 0 }); // remove 0 values of deleted annotations
    for (int i = sizeof(aoAnnotations) - 1; i >= 0; i-- ) 
    {
	object ann = aoAnnotations[i];
	if ( ann->status() >= 0 && i >= from_obj && ( !to_obj || i < to_obj ) )
	    annotations += ({ ann });
    }
    return annotations;
}

/**
 * This function returns a copied list of all annotations of this
 * object which match a given classtype
 *  
 * @return the array of annotations
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>) 
 * @see get_annotations
 */
array(object) get_annotations_by_class(int class_id)
{
    array(object) tmp=get_annotations();
    foreach(tmp, object curr)
        if((curr->get_object_class() & class_id)==0)
            tmp-=({curr});
    return tmp;
}

object get_annotation_byid(string name)
{
  array(object) tmp=get_annotations();
  foreach(tmp, object ann) {
    if ( ann->get_object_id() == (int)name )
      return ann;
  }
  return 0;
}

/**
 * Get the object we are annotating.
 *  
 * @return the object we annotated
 */
object get_annotating()
{
    return oAnnotates;
}

/**
 * Set the annotating object.
 *  
 * @param object obj - the annotating object
 */
void set_annotating(object obj)
{
    if ( !objectp(oAnnotates) || CALLER->this() == oAnnotates->this() )
	oAnnotates = obj;
    require_save(STORE_ANNOTS);
    update_path();
}

/**
 * Get only the annotations for a specific user. If no user is given
 * this_user() will be used.
 *  
 * @param object|void user - the user to get the annotations for
 * @return array of annotations readable by the user
 * @see get_annotations
 */
array(object) 
get_annotations_for(object|void user, void|int from_obj, void|int to_obj)
{
    if ( !objectp(user) ) user = this_user();
    
    array(object) user_annotations = ({ });
    if ( !intp(from_obj) )
	from_obj = 1;

    foreach ( aoAnnotations, object annotation ) {
	if ( !objectp(annotation) ) continue;

	mixed err = catch {
	    _SECURITY->check_access(
		annotation, user, SANCTION_READ, ROLE_READ_ALL, false);
	};
	if ( err == 0 )
	    user_annotations = ({ annotation }) + user_annotations;
    }
    if ( !to_obj )
	return user_annotations[from_obj-1..];
    return user_annotations[from_obj-1..to_obj-1];
}


/**
 * Retrieve annotations is for storing the annotations in the database.
 * Only the global _Database object is able to call this function.
 *  
 * @return Mapping of object data.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see restore_annotations
 */
final mapping retrieve_annotations()
{
    if ( CALLER != _Database )
	THROW("Caller is not the Database object !", E_ACCESS);

    return ([ "Annotations":aoAnnotations,
	      "Annotates": oAnnotates, ]);
}

/**
 * Called by database to restore the object data again upon loading.
 * 
 * @param mixed data - the object data
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see retrieve_annotations
 */
final void
restore_annotations(mixed data)
{
    if ( CALLER != _Database )
	THROW("Caller is not the Database object !", E_ACCESS);

    aoAnnotations = data["Annotations"];
    oAnnotates = data["Annotates"];
    if ( !arrayp(aoAnnotations) )
    {
	aoAnnotations = ({ });
        require_save(STORE_ANNOTS);
    }
}

/**
 * Returns the annotations of this object, optionally filtered by object
 * class, attribute values or pagination.
 * The description of the filters and sort options can be found in the
 * filter_objects_array() function of the "searching" module.
 *
 * Example:
 * Return all the annotations that have been created or last modified by user
 * "root" in the last 24 hours, recursively and sorted by modification date
 * (newest first) and return only the first 10 results:
 * get_inventory_filtered(
 *   ({  // filters:
 *     ({ "-", "!class", CLASS_DOCUMENT }),
 *     ({ "-", "attribute", "DOC_LAST_MODIFIED", "<", time()-86400 }),
 *     ({ "+", "function", "get_creator", "==", USER("root") }),
 *     ({ "+", "attribute", "DOC_USER_MODIFIED", "==", USER("root") }),
 *   }),
 *   ({  // sort:
 *     ({ ">", "attribute", "DOC_LAST_MODIFIED" })
 *   }), 0, 10 );
 *
 * @param filters (optional) an array of filters (each an array as described
 *   in the "searching" module) that specify which objects to return
 * @param sort (optional) an array of sort entries (each an array as described
 *   in the "searching" module) that specify the order of the items
 * @param offset (optional) only return the objects starting at (and including)
 *   this index
 * @param length (optional) only return a maximum of this many objects
 * @param max_depth (optional) max recursion depth (0 = only return
 *   annotations of this object)
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
mapping get_annotations_paginated ( array|void filters, array|void sort, int|void offset, int|void length, int|void max_depth )
{
  return get_module( "searching" )->paginate_object_array( low_get_annotations_recursive( 0, max_depth ), filters, sort, offset, length );
}

/**
 * Returns the annotations of this object, optionally filtered, sorted and
 * limited by offset and length. This returns the same as the "objects" index
 * in the result of get_annotations_paginated() and is here for compatibility
 * reasons and ease of use (if you don't need pagination information).
 *
 * @see get_annotations_paginated
 */
array get_annotations_filtered ( array|void filters, array|void sort, int|void offset, int|void length, int|void max_depth )
{
  return get_annotations_paginated( filters, sort, offset, length, max_depth )["objects"];
}

protected array low_get_annotations_recursive ( int depth, void|int max_depth )
{
  if ( max_depth > 0 && depth > max_depth ) return ({ });
  array annotations = ({ });
  foreach ( aoAnnotations, mixed annotation ) {
    if ( !objectp(annotation) ) continue;
    annotations += ({ annotation });
    mixed rec_res = annotation->low_get_annotations_recursive( depth + 1, max_depth );
    if ( arrayp(rec_res) ) annotations += rec_res;
  }
  return annotations;
}
