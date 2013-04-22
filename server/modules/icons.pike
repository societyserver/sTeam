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
 * $Id: icons.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: icons.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <attributes.h>
#include <events.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <types.h>

//! This is the icon module. It keeps track of all classes and maps
//! an icon document for each class. If no individual icon is set in
//! an object the OBJ_ICON attribute is acquired from this object and
//! so the default icon is retrieved. Obviously this enables the admin
//! to replace the default system icons at this place.
//!
//! @note
//! Whats missing here is an interface to set the icons
//! which is really not an issue of this module, but an appropriate
//! script should do the work and call the functions here.

static mapping mIcons = ([ ]);

#define ATTR_ICONSETS "iconsets"

void load_module ()
{
  // remove invalid iconsets:
  array iconsets = query_attribute( ATTR_ICONSETS ) || ({ });
  int iconsets_changed = 0;
  foreach ( iconsets, mixed iconset ) {
    if ( !objectp(iconset) || iconset->status() == PSTAT_DELETED ||
         iconset->status() == PSTAT_FAIL_DELETED ) {
      iconsets -= ({ iconset });
      iconsets_changed = 1;
    }
  }
  if ( iconsets_changed ) set_attribute( ATTR_ICONSETS, iconsets );
}

void install_module()
{
}

object init_icon ( string path ) {
  object icon;
  if ( catch ( icon = _FILEPATH->path_to_object( path ) ) || !objectp(icon) ) {
    werror( "icons module: could not initialize icon '%s'\n", path );
    return UNDEFINED;
  }
  return icon;
}

void init_icons()
{
    mixed err = catch {
    mIcons = ([
	CLASS_DATE:
	    init_icon("/images/doctypes/type_date.gif"),
	CLASS_DATE|CLASS_LINK:
	    init_icon("/images/doctypes/type_date_lnk.gif"),            
	CLASS_CALENDAR:
	    init_icon("/images/doctypes/type_calendar.gif"),
	CLASS_CALENDAR|CLASS_LINK:
	    init_icon("/images/doctypes/type_calendar_lnk.gif"), 
	CLASS_TRASHBIN:
	    init_icon("/images/doctypes/trashbin.gif"),
	CLASS_FACTORY:
	    init_icon("/images/doctypes/type_factory.gif"),
	CLASS_ROOM:
	    init_icon("/images/doctypes/type_area.gif"),
	CLASS_ROOM|CLASS_LINK:
	    init_icon("/images/doctypes/type_gate.gif"),
	CLASS_EXIT:
	    init_icon("/images/doctypes/type_gate.gif"),
	CLASS_EXIT|CLASS_LINK:
	    init_icon("/images/doctypes/type_gate.gif"),
	CLASS_USER:
	    init_icon("/images/doctypes/user_unknown.jpg"),
	CLASS_GROUP:
	    init_icon("/images/doctypes/type_group.gif"),
	CLASS_CONTAINER:
	    init_icon("/images/doctypes/type_folder.gif"),
	CLASS_CONTAINER|CLASS_LINK:
	    init_icon("/images/doctypes/type_folder_lnk.gif"),
	CLASS_DOCUMENT:
	    init_icon("/images/doctypes/type_generic.gif"),
	CLASS_DOCUMENT|CLASS_LINK:
	    init_icon("/images/doctypes/type_generic_lnk.gif"),
	"text/html":
            init_icon("/images/doctypes/type_html.gif"),
	CLASS_DOCHTML:
	    init_icon("/images/doctypes/type_html.gif"),
	CLASS_DOCHTML|CLASS_LINK:
	    init_icon("/images/doctypes/type_html_lnk.gif"),
	"image/*":
            init_icon("/images/doctypes/type_img.gif"),
	CLASS_IMAGE:
            init_icon("/images/doctypes/type_img.gif"),
	CLASS_IMAGE|CLASS_LINK:
	    init_icon("/images/doctypes/type_img_lnk.gif"),
	CLASS_DOCEXTERN:
	    init_icon("/images/doctypes/type_references.gif"),
	CLASS_DOCEXTERN|CLASS_LINK:
	    init_icon("/images/doctypes/type_references_lnk.gif"),
	"source/pike":
            init_icon("/images/doctypes/type_pike.gif"),
	CLASS_SCRIPT:
	    init_icon("/images/doctypes/type_pike.gif"),
	CLASS_SCRIPT|CLASS_LINK:
	    init_icon("/images/doctypes/type_pike_lnk.gif"),
	CLASS_DOCLPC:
	    init_icon("/images/doctypes/type_pike.gif"),
	CLASS_DOCLPC|CLASS_LINK:
	    init_icon("/images/doctypes/type_pike_lnk.gif"),
	CLASS_OBJECT:
	    init_icon("/images/doctypes/type_object.gif"),
	CLASS_OBJECT|CLASS_LINK:
	    init_icon("/images/doctypes/type_object_lnk.gif"),
	CLASS_MESSAGEBOARD: 
	    init_icon("/images/doctypes/type_messages.gif"),
	CLASS_MESSAGEBOARD|CLASS_LINK: 
	    init_icon("/images/doctypes/type_messages_lnk.gif"),
	"video/*":
	    init_icon("/images/doctypes/type_movie.gif"),
	"audio/*":
	    init_icon("/images/doctypes/type_audio.gif"),
	"application/pdf":
	    init_icon("/images/doctypes/type_pdf.gif"),
	]);
    };
    if ( err != 0 ) {
	LOG("While installing Icons-module: One or more images not found !");
	LOG(sprintf("%s\n%O", err[0], err[1]));
        mIcons = ([ ]);
    }
    require_save(STORE_ICONS);
}

void init_module()
{
    
    add_data_storage(STORE_ICONS, store_icons, restore_icons, 1);
    if ( !objectp(MODULE_GROUPS) || !objectp(_ROOTROOM) ) 
	return; // first start of server
    
    if ( _FILEPATH->get_object_in_cont(_ROOTROOM, "images") == 0 ) {
      LOG("Warning: no /images container found for icons module ...");
    }
     
    set_attribute(OBJ_DESC, "This is the icons module. Here each class "+
		  "is associated an appropriate icon.");

    LOG("Initializing icons ...");
    init_icons();
}

bool keep_acquire(object o, mixed key, mixed val)
{
  return false; // drop acquire if icon is set
}

mixed set_attribute(string|int key, mixed val)
{
  if ( key == OBJ_ICON || intp(key) ) {
    return 0;
  }
  return ::set_attribute(key, val);
}

mixed query_attribute(string|int key)
{
  if ( key == OBJ_ICON )
    return get_default_icon( CALLER );
  return ::query_attribute(key);
}

array get_iconsets ()
{
  array iconsets = query_attribute( ATTR_ICONSETS ) || ({ });
  if ( !arrayp(iconsets) )
    return ({ });
  return copy_value( iconsets );
}

void add_iconset ( object iconset )
{
  if ( !functionp( iconset->get_default_icon ) )
    THROW( "Iconset needs to implement get_default_icon(obj) and "
           "get_icon_by_name(name) functions.", E_ERROR );
  array iconsets = query_attribute( ATTR_ICONSETS ) || ({ });
  if ( search( iconsets, iconset ) >= 0 )
    return;
  iconsets += ({ iconset });
  set_attribute( ATTR_ICONSETS, iconsets );
}

void remove_iconset ( object iconset )
{
  array iconsets = query_attribute( ATTR_ICONSETS );
  if ( search( iconsets, iconset ) < 0 )
    return;
  iconsets -= ({ iconset });
  set_attribute( ATTR_ICONSETS, iconsets );
}

object get_default_icon ( object obj )
{
  foreach ( query_attribute( ATTR_ICONSETS ) || ({ }), object iconset ) {
    if ( !objectp(iconset) || !functionp(iconset->get_default_icon) ) continue;
    object icon = iconset->get_default_icon( obj );
    if ( objectp(icon) )
      return icon;
  }
  return get_icon( obj->get_object_class(),
                   obj->query_attribute( DOC_MIME_TYPE ) );
}

object get_icon_by_name ( string name )
{
  foreach ( query_attribute( ATTR_ICONSETS ) || ({ }), object iconset ) {
    if ( !objectp(iconset) || !functionp(iconset->get_icon_by_name) ) continue;
    object icon = iconset->get_icon_by_name( name );
    if ( objectp(icon) )
      return icon;
    return UNDEFINED;
  }
}

/**
 * Get an icon for a specific object class or mime-type.
 *  
 * @param int|string type - the object class
 * @param string|void mtype - the mime-type
 * @return an icon document.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object get_icon(int type, string|void mtype)
{
    if ( stringp(mtype) )
    {
	if ( objectp(mIcons[mtype]) )
	    return mIcons[mtype];
	
	// global type registration 
	string glob, loc;
	sscanf(mtype,"%s/%s", glob, loc);
	if ( mIcons[glob+"/*"] )
	    return mIcons[glob+"/*"];
    }

    int rtype = type;
    if ( type & CLASS_LINK ) {
	object caller = CALLER;
	object link = caller->get_link_object();
	type = (objectp(link) ? link->get_object_class() : 1);
    }

    int t = 0;
	
    for ( int i = 31; i >= 0; i-- ) {
	if ( (type & (1<<i)) && objectp(mIcons[(1<<i)]) ) {
	    t = 1 << i;
	    break;
	}
    }
    if ( t != 0 ) {
	if ( rtype & CLASS_LINK )
	    return mIcons[t|CLASS_LINK];
	else
	    return mIcons[t];
    }
    return 0;
}

void set_icon(int|string type, object icon)
{
    _SECURITY->access_write(0, this(), CALLER);
    mIcons[type] = icon;
    require_save(STORE_ICONS);
}

mapping get_icons()
{
    return copy_value(mIcons);
}

/**
 * Restore callback function called by _Database to restore data.
 *  
 * @param mixed data - the data to restore.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>)
 * @author conversion to indexed storage by Ludger Merkens
 */
void restore_icons(mixed data, string|void index)
{
    if (CALLER != _Database )
	THROW("Caller is not Database !", E_ACCESS);

    mapping output = ([]);

    if (!zero_type(index))
    {
        if (index[0]=='\"')
            mIcons[index[1..]] = data;
        else
            mIcons[(int)index[1..]] = data;
    }
    else
    {
        foreach (indices(data), string ndx)
        {
            if (ndx[0]=='\"')
                mIcons[ndx[1..]] = data[ndx];
            else
                mIcons[(int)ndx[1..]] = data[ndx];
        }
    }
}

/**
 * Function to save data called by the _Database.
 *  
 * @return Mapping of icon save data.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @author conversion to indexed storage by Ludger Merkens
 */
mixed store_icons(string|void index)
{
    if (CALLER != _Database )
	THROW("Caller is not Database !", E_ACCESS);
    if (zero_type(index)) {
        mapping output = ([]);
        foreach(indices(mIcons), mixed ndx)
        {
            if (stringp(ndx))
                output["\""+ndx]= mIcons[ndx];
            else
                output["#"+(string)ndx]= mIcons[ndx];
        }
        return output;
    }
    else
    {
        if (index[0]=='\"')
            return mIcons[index[1..]];
        else
            return mIcons[(int)index[1..]];
    }
}

string get_identifier() { return "icons"; }
