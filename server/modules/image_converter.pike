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
 * $Id: image_converter.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: image_converter.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

import htmllib;

#include <classes.h>
#include <attributes.h>
#include <macros.h>

#define _FILEPATH _Server->get_module("filepath:tree")
#define MODULE_FONT_CACHE _Server->get_module("fonts:TTF")


//! Converts images from one format to another. The most
//! important function is the get_image() function of this module.
//!

/**
 * Get a font according to font-description
 * substitutes the default font, if no matching font can be found.
 * @param type    - the fonts name
 * @param style   - 0 plain, 1 bold, 2 italic (bitwise or to use combinations)
 * @param size    - fontsize
 * @author Ludger Merkens
 */
private Image.Font get_font(string type, int style, int size)
{
    Image.Font oTTF;
    if ( objectp(MODULE_FONT_CACHE) )
    {
        oTTF=MODULE_FONT_CACHE->get_font_object(type, style);
        
        if (objectp(oTTF))
        {
            oTTF = oTTF();
            oTTF->set_height(size);
            return oTTF;
        }
    }
    return Image.Font();
}

private array(int) __text_extends(array(string) list, object font)
{
    mapping(int:int) width_cache=([]);
    array(int) result = ({});
    
    foreach(list, string s)
    {
        int width=0, w;
        foreach(s/"", string c)
        {
            if (w=width_cache[c[0]])
                width+=w;
            else
            {
                width_cache[c[0]]=w=font->write(c)->xsize();
                width+=w;
            }
        }
        result += ({ width });
    }
    return result;
}

private array(string) wrap_with_font(string from, int width, object font)
{
    //    array(int) charlens = font->text_extends(from/"");
    //    doesn't work inspite of the Pike Dokumentation
    array(int) charlens = __text_extends(from/"", font);
    int i,sz;
    int last_pos = 0;
    int curr_len = 0;
    array(string) result = ({});
    
    for (i=0,sz=sizeof(charlens);i<sz;i++)
    {
        if (from[i]=='\n')
        {
            result += ({ from[last_pos..i-1] });
            curr_len = 0;
            i++;
            last_pos = i;
        }
        else
        {
            if ((curr_len < width) ||
                (font->write(from[last_pos..i-1])->xsize()) < width)
                curr_len += charlens[i];
            else
            {
                if (from[i]==' ')
                    while (from[i]==' ') i++;
                else {
                    int oldi=i;
                    while (from[i]!=' ' && i>last_pos) i--;
                    i++;
                    if (i==last_pos) i=oldi;
                }
                result += ({ from[last_pos..i-1] });
                last_pos = i;
                curr_len = 0;
            }
        }
    }
    result += ({ from[last_pos..sz] });
    LOG("number of lines wrapped is"+sizeof(result));
    return result;
}

private object hard_default_icon(int iOclass)
{
    string sImagePath;
    
    if (iOclass & CLASS_CONTAINER)
        if (iOclass & CLASS_ROOM)
            sImagePath = "/images/doctypes/type_room.gif";
        else
            sImagePath = "/images/doctypes/type_folder.gif";
    
    if (iOclass & CLASS_DOCLPC)
        sImagePath = "/images/doctypes/type_object.gif";
    
    object oIcon=_FILEPATH->path_to_object(sImagePath);
}

private Image.Layer image_from_object(object oIcon)
{
    string sMime = oIcon->query_attribute(DOC_MIME_TYPE);
    if (!sMime)
        sMime = "ANY";
    else
        sscanf(sMime, "image/%s", sMime);
    sMime = upper_case(sMime);

    LOG("sMime in image_from_object is "+sMime);
    string content = oIcon->get_content();
    if (strlen(content))
    {
        object oInputImageCoder = Image[sMime];
        if (objectp(oInputImageCoder))
            if (sMime=="GIF")
                return oInputImageCoder->decode_layer(content)->image();
            else
                return oInputImageCoder->decode(content);
    }
}


/**
 * Get an image representation of given (container) object (if any)
 *
 * @param obj      - the object to represent
 * @param x        - x-size of image
 * @param y        - y-size of image
 * @param encoding - an image/encoding (e.g. image/jpeg)
 * @return a string containing the image of given encoding
 * @author Ludger Merkens
 */
string get_image(object obj, int x, int y, string encoding)
{
    array(object) aoInv;
    Image.Image oLine;
    Image.Image oIcon;
    object oTempImage;
    
    string sImagePath = "/images/doctypes/type_generic.gif";
    
    if (!(obj->get_object_class() & CLASS_CONTAINER))
        return 0;

    aoInv = obj->get_inventory();
    if (!arrayp(aoInv))
        return 0;

    mapping mLayer = obj->query_attribute("WHITEBOARD_ATTR_LAYER_INFO");
    if (mLayer)
    {
        foreach(aoInv, object o)
            LOG("["+o->get_object_id()+"]");
        mLayer -= ({"size"});
        mapping(int:int) LayTable = ([]);
        foreach(indices(mLayer), int layer)
            LayTable[mLayer[layer]]=layer;
        array(object) ordered = allocate(sizeof(mLayer));

        int p;
        for (int i=0; i<sizeof(aoInv); i++)
        {
            p=LayTable[aoInv[i]->get_object_id()];
            if (!zero_type(p))
            {
                LOG("p for "+aoInv[i]->get_object_id()+" is "+p+"("+
                    aoInv[i]->get_identifier()+")");
                ordered[p]=aoInv[i];
                aoInv[i]=0;
            }
        }
        aoInv += reverse(ordered);
        aoInv -= ({ 0});
        foreach(aoInv, object o)
            LOG("["+o->get_object_id()+"]");
    }
    if (!x || x < 0)
    {
        x = (int) obj->query_attribute(CONT_SIZE_X);
        if (!x) x = 1646;
    }
    if (!y || y < 0)
    {
        y = (int) obj->query_attribute(CONT_SIZE_Y);
        if (!y) y = 1442;
    }

    object oImage = Image.Image(x, y);
    //    object oColor = Image.Color()
    oImage->box(0,0,x,y,255,255,255);
    oImage->box(0,0,0,0,0,0,0);
       // to do ... sort by WHITEBOARD_ATTR_LAYER_INFO

    foreach(aoInv, object graphics)
    {
        LOG("I:"+sprintf("%O", graphics));
        int x1 = (int) graphics->query_attribute(OBJ_POSITION_X);
        int w = (int) graphics->query_attribute(DRAWING_WIDTH);
        int x2 = (int) x1+ w;
        int y1 = (int) graphics->query_attribute(OBJ_POSITION_Y);
        int h = (int) graphics->query_attribute(DRAWING_HEIGHT);
        int y2 = (int) y1+h;
        int iColor = graphics->query_attribute(DRAWING_COLOR);

        int r,g,b;

        b = iColor & 511;
        iColor = iColor >> 8;
        g = iColor & 511;
        iColor = iColor >> 8;
        r = iColor & 511;
        
        int iOclass;

        if (!((iOclass = graphics->get_object_class()) &
              (CLASS_DRAWING|CLASS_USER )))
        {
            oIcon=graphics->query_attribute(OBJ_ICON);
            if (!oIcon)
                oIcon= hard_default_icon(iOclass);
            
            if (oIcon)
            {
                catch {oTempImage = image_from_object(oIcon);};
                if (oTempImage)
                {
                    oLine = Image.Font()->write(graphics->get_identifier());
                    oImage->paste_alpha_color(
                        oLine, 0,0,0,
                        x1,
                        (y1+oTempImage->ysize())
                        );
                    oImage->paste(oTempImage, x1-(oTempImage->xsize()/2)+(oLine->xsize()/2), y1);
                }
            }
        }
            
        switch (graphics->query_attribute(DRAWING_TYPE))
        {
          case DRAWING_LINE :
              if (graphics->query_attribute("LINE_ATTR_DIRECTION") == 1)
                  oImage->line(x1, y1, x2, y2, r, g, b);
              else
                  oImage->line(x1, y2, x2, y1, r, g, b);
              break;
          case DRAWING_RECTANGLE:
              oImage->line(x1, y1, x2, y1, r, g, b); 
              oImage->line(x1, y1, x1, y2, r, g, b);
              oImage->line(x2, y1, x2, y2, r, g, b);
              oImage->line(x1, y2, x2, y2, r, g, b);
              break;
              //case DRAWING_TRIANGLE:
              //case DRAWING_POLYGON:
              //case DRAWO
          case DRAWING_CIRCLE :
              oImage->circle((x1+x2)/2,(y1+y2)/2,
                             (int)(w/2), (int) (h/2), r, g, b);//, 0, 255, 0);
              break;

          case 9: // embedded image
              oIcon = graphics->query_attribute("IMAGE_ATTR_IMAGEOBJECT");
              if (oIcon)
              {
                  catch {oTempImage = image_from_object(oIcon);};
                  if (oTempImage)
                  {
                      float xf = (float)w /(float)oTempImage->xsize();
                      float yf = (float)h /(float)oTempImage->ysize();
                      oImage->paste(oTempImage->scale(xf,yf), x1, y1);
                  }
              }
              break;
          case 10: // filled rectangle
              oImage->box(x1,y1,x2,y2, r,g,b);
              break;
          case 11: // filled circle
              oTempImage = Image.Image(w,h);
              oTempImage->circle(w/2, h/2, w/2, h/2, 255, 255, 255);
              oImage->paste_alpha_color(
                  oTempImage->select_from(w/2,h/2), r,g,b,x1,y1);
              break;
          case DRAWING_TEXT : // obsolete, but for compatibility reasons.
          case 16 : // multiline text
              string fontfile = graphics->query_attribute("TEXT_ATTR_TYPE");
              int fontstyle = graphics->query_attribute("TEXT_ATTR_STYLE");
              string textlabel = graphics->query_attribute("TEXT_ATTR_TEXT");
              int fontsize = graphics->query_attribute("TEXT_ATTR_SIZE");
              
              object oFont = get_font(fontfile, fontstyle, fontsize);

              /*if ( stringp(textlabel) )
              {
                  oLine = oFont->write(textlabel);
                  oImage->paste_alpha_color(oLine, r,g,b, x1, y1);
                  }*/
              if (stringp(textlabel))
              {
                  array(string) splitted =
                      wrap_with_font(textlabel, w, oFont);
                  for (int i=0;i<sizeof(splitted);i++)
                  {
                      LOG("Line"+i+":"+splitted[i]);
                      oLine = oFont->write(splitted[i]);
                      oImage->paste_alpha_color(oLine, r,g,b, x1, y1);
                      y1 += (int)(oLine->ysize()*1.2);
                  }
              }
              break;
          default:
              LOG("unknown graphixtype:"+
                  graphics->query_attribute(DRAWING_TYPE));
        }
    }
    if (!encoding) // use a free one by default!
        encoding = "image/jpeg";

    string sImageCoder;
    sscanf(encoding, "image/%s", sImageCoder);
    sImageCoder = upper_case(sImageCoder);
    object oImageCoder = Image[sImageCoder];
    
    if (!oImageCoder)
        return 0;

    return oImageCoder->encode(oImage);
}

string get_image_map(object obj, void|mapping vars)
{
    array(object) aoInv;
    object oLine;
    string sImageMap;
    string sImagePath = "/images/doctypes/type_generic.gif";
    
    if (!(obj->get_object_class() & CLASS_CONTAINER))
        return 0;

    aoInv = obj->get_inventory();
    if (!arrayp(aoInv))
        return 0;

    sImageMap = "<map name=\""+obj->get_object_id()+"\">\n";
    foreach(aoInv, object graphics)
    {
        int iOclass;

        if (!((iOclass = graphics->get_object_class())
              & (CLASS_DRAWING|CLASS_USER)))
        {
            int x1 = (int) graphics->query_attribute(OBJ_POSITION_X);
            int w = (int) graphics->query_attribute(DRAWING_WIDTH);
            int y1 = (int) graphics->query_attribute(OBJ_POSITION_Y);
            int h = (int) graphics->query_attribute(DRAWING_HEIGHT);
            
            if (!w || !h)
            {
                object oIcon = graphics->query_attribute(OBJ_ICON);
		if ( !objectp(oIcon) )
		    continue;
                string sMime = oIcon->query_attribute(DOC_MIME_TYPE);
                if (!sMime)
                    sMime = "ANY";
                else
                    sscanf(sMime, "image/%s", sMime);
                sMime = upper_case(sMime);

		MESSAGE("Module"+sMime);
                object oInputImageCoder = Image[sMime];
                if (objectp(oInputImageCoder))
                {
		    MESSAGE("ImageCoder:"+master()->describe_object(oInputImageCoder));
                    mapping mIconData;
                    if (sMime == "GIF")
                        mIconData =
                            oInputImageCoder->decode_map(oIcon->get_content());
                    else
                        mIconData =
                            oInputImageCoder->_decode(oIcon->get_content());
                    w = mIconData["xsize"];
                    h = mIconData["ysize"];
                }
            }
            
            sImageMap +="  <area shape=\"rect\" coords=\""+
                x1+ ", " + y1 + ", " + (x1+w) + ", " + (y1+h) +"\" "+
		href_link_navigate_postfix(graphics, vars->prefix, vars->postfix)+"/>\n";

            oLine = Image.Font()->write(graphics->get_identifier());
            sImageMap +="  <area shape=\"rect\" coords=\""+
                (x1+(w/2)-(oLine->xsize()/2))+", "+
                (y1+h+5)+", "+
                (x1+(w/2)+(oLine->xsize()/2))+", "+
                (y1+h+5+oLine->ysize())+"\" "+
		href_link_navigate_postfix(graphics, vars->prefix, vars->postfix)+"/>\n";
        }
    }
    int x = -1;
    int y = -1;
    if (stringp(vars["x"])) x = (int)vars["x"];
    if (intp(vars["x"]))    x = vars["x"];
    if (stringp(vars["y"])) y = (int)vars["y"];   
    if (intp(vars["x"]))    y = vars["y"];
    sImageMap += "</map> <img src=\"/scripts/svg.svg?object="+obj->get_object_id()+
        "&amp;enc=image/jpeg&amp;x="+x+"&amp;y="+y+"\" usemap=\"#"+obj->get_object_id()+"\"/>\n";

    return sImageMap;
}

string get_identifier() { return "Converter:IMAGE"; }
