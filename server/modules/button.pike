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
 * $Id: button.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: button.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <database.h>
#include <macros.h>

Image.Layer layer_slice( Image.Layer l, int from, int to )
{
  return Image.Layer( ([
    "image":l->image()->copy( from,0, to-1, l->ysize()-1 ),
    "alpha":l->alpha()->copy( from,0, to-1, l->ysize()-1 ),
  ]) );
}

Image.Layer stretch_layer( Image.Layer o, int x1, int x2, int w )
{
  Image.Layer l, m, r;
  int leftovers = w - (x1 + (o->xsize()-x2) );
  object oo = o;

  l = layer_slice( o, 0, x1 );
  m = layer_slice( o, x1+1, x2-1 );
  r = layer_slice( o, x2, o->xsize() );

  m->set_image( m->image()->scale( leftovers, l->ysize() ),
                m->alpha()->scale( leftovers, l->ysize() ));

  l->set_offset(  0,0 );
  m->set_offset( x1,0 );
  r->set_offset( w-r->xsize(),0 );
  o = Image.lay( ({ l, m, r }) );
  o->set_mode( oo->mode() );
  o->set_alpha_value( oo->alpha_value() );
  return o;
}

mapping load_icon(string path) 
{
    werror("Loading Icon="+path+"\n");
}


array(Image.Layer) load_layers(string path)
{
    object obj = _FILEPATH->path_to_object(path);
    string data = obj->get_content();
    return Image.decode_layers(data);
}

Image.Font resolve_font(string font)
{
    object fontobj = Image.Font();
    
    fontobj->load("server/modules/test.fnt");
    return fontobj;
}

array(Image.Layer)|mapping draw_button(mapping args, string text)
{
  Image.Image  text_img;
  mapping      icon;

  Image.Layer background;
  Image.Layer frame;
  Image.Layer mask;

  int left, right, top, middle, bottom; /* offsets */
  int req_width, noframe;

  mapping ll = ([]);

  void set_image( array layers )
  {
    foreach( layers||({}), object l )
    {
      if(!l->get_misc_value( "name" ) ) // Hm. Probably PSD
        continue;

      ll[lower_case(l->get_misc_value( "name" ))] = l;
      switch( lower_case(l->get_misc_value( "name" )) )
      {
       case "background": background = l; break;
       case "frame":      frame = l;     break;
       case "mask":       mask = l;     break;
      }
    }
  };

  if( args->border_image )
  {
      array(Image.Layer)|mapping tmp = load_layers(args->border_image);
    if (mappingp(tmp))
      if (tmp->error == 401)
	return tmp;
      else
	error("GButton: Failed to load frame image: %O\n",
	      args->border_image);
    set_image( tmp );
  }


  //  otherwise load default images
  if ( !frame && !background && !mask )
  {
    string data = Stdio.read_file("gbutton.xcf");
    if (!data)
      error ("Failed to load default frame image "
	     "(roxen-images/gbutton.xcf): " + strerror (errno()));
    mixed err = catch {
      set_image(Image.XCF.decode_layers(data));
    };
    if( !frame )
      if (err) {
	catch (err[0] = "Failed to decode default frame image "
	       "(gbutton.xcf): " + err[0]);
	throw (err);
      }
      else
	error("Failed to decode default frame image "
	      "(roxen-images/gbutton.xcf).\n");
  }

  if( !frame )
  {
    noframe = 1;
    frame = background || mask; // for sizes offsets et.al.
  }
  
  // Translate frame image to 0,0 (left layers are most likely to the
  // left of the frame image)
  int x0 = frame->xoffset();
  int y0 = frame->yoffset();
  if( x0 || y0 )
    foreach( values( ll ), object l )
    {
      int x = l->xoffset();
      int y = l->yoffset();
      l->set_offset( x-x0, y-y0 );
    }

  if( !mask )
    mask = frame;

  array x = ({});
  array y = ({});

  foreach( frame->get_misc_value( "image_guides" ), object g )
    if( g->vertical )
      x += ({ g->pos - x0 });
    else
      y += ({ g->pos - y0 });

  sort( y );
  sort( x );

  if(sizeof( x ) < 2)
    x = ({ 5, frame->xsize()-5 });

  if(sizeof( y ) < 2)
    y = ({ 2, frame->ysize()-2 });

  left = x[0]; right = x[-1];    top = y[0]; middle = y[1]; bottom = y[-1];
  right = frame->xsize()-right;

  //  Text height depends on which guides we should align to
  int text_height;
  switch (args->icva) {
  case "above":
    text_height = bottom - middle;
    break;
  case "below":
    text_height = middle - top;
    break;
  default:
  case "middle":
    text_height = bottom - top;
    break;
  }

  //  Get icon
  if (args->icn)
      icon = load_icon(args->icn);
  else if (args->icd)
      icon = load_icon(args->icd);

  int i_width = icon && icon->img->xsize();
  int i_height = icon && icon->img->ysize();
  int i_spc = i_width && sizeof(text) && 5;

  //  Generate text
  if (sizeof(text))
  {
    int os, dir;
    Image.Font button_font;
    int th = text_height;
    do
    {
      button_font = resolve_font( args->font+" "+th );
      text_img = button_font->write(text);
      os = text_img->ysize();
      if( !dir )
        if( os < text_height )
          dir = 1;
        else if( os > text_height )
          dir =-1;
      if( dir > 0 && os > text_height ) break;
      else if( dir < 0 && os < text_height ) dir = 1;
      else if( os == text_height ) break;
      th += dir;
    } while( (text_img->ysize() - text_height)
             && (th>0 && th<text_height*2));

    // fonts that can not be scaled.
    if( abs(text_img->ysize() - text_height)>2 )
      text_img = text_img->scale(0, text_height );
    else
    {
      int o = text_img->ysize() - text_height; 
      top -= o;
      middle -= o/2;
    }
    if (args->cnd)
      text_img = text_img->scale((int) round(text_img->xsize() * 0.8),
				 text_img->ysize());
  } else
    text_height = 0;

  int t_width = text_img && text_img->xsize();

  //  Compute text and icon placement. Only incorporate icon width/spacing if
  //  it's placed inline with the text.
  req_width = t_width + left + right;
  if ((args->icva || "middle") == "middle")
    req_width += i_width + i_spc;
  if (args->wi && (req_width < args->wi))
    req_width = args->wi;

  int icn_x, icn_y, txt_x, txt_y;

  //  Are text and icon lined up or on separate lines?
  switch (args->icva) {
  case "above":
  case "below":
    //  Note: This requires _three_ guidelines! Icon and text can only be
    //  horizontally centered
    icn_x = left + (req_width - right - left - i_width) / 2;
    txt_x = left + (req_width - right - left - t_width) / 2;
    if (args->icva == "above" || !text_height) {
      txt_y = middle;
      icn_y = top + ((text_height ? middle : bottom) - top - i_height) / 2;
    } else {
      txt_y = top;
      icn_y = middle + (bottom - middle - i_height) / 2;
    }
    break;

  default:
  case "middle":
    //  Center icon vertically on same line as text
    icn_y = icon && (frame->ysize() - icon->img->ysize()) / 2;
    txt_y = top;
    
    switch (args->al)
    {
    case "left":
      //  Allow icon alignment: left, right
      switch (args->ica)
      {
      case "left":
	icn_x = left;
	txt_x = icn_x + i_width + i_spc;
	break;
      default:
      case "right":
	txt_x = left;
	icn_x = req_width - right - i_width;
	break;
      }
    break;

    default:
    case "center":
    case "middle":
      //  Allow icon alignment:
      //  left, center, center-before, center-after, right
      switch (args->ica)
      {
      case "left":
	icn_x = left;
	txt_x = (req_width - right - left - i_width - i_spc - t_width) / 2;
	txt_x += icn_x + i_width + i_spc;
	break;
      default:
      case "center":
      case "center_before":
      case "center-before":
	icn_x = (req_width - i_width - i_spc - t_width) / 2;
	txt_x = icn_x + i_width + i_spc;
	break;
      case "center_after":
      case "center-after":
	txt_x = (req_width - i_width - i_spc - t_width) / 2;
	icn_x = txt_x + t_width + i_spc;
	break;
      case "right":
	icn_x = req_width - right - i_width;
	txt_x = left + (icn_x - i_spc - t_width - left) / 2;
	break;
      }
      break;
      
    case "right":
      //  Allow icon alignment: left, right
      switch (args->ica)
      {
      default:
      case "left":
	icn_x = left;
	txt_x = req_width - right - t_width;
	break;
      case "right":
	icn_x = req_width - right - i_width;
	txt_x = icn_x - i_spc - t_width;
	break;
      }
      break;
    }
    break;
  }

  if( args->extra_frame_layers )
  {
    array l = ({ });
    foreach( args->extra_frame_layers/",", string q )
      l += ({ ll[q] });
    l-=({ 0 });
    if( sizeof( l ) )
      frame = Image.lay( l+(noframe?({}):({frame})) );
  }

  if( args->extra_mask_layers )
  {
    array l = ({ });
    foreach( args->extra_mask_layers/",", string q )
      l += ({ ll[q] });
    l-=({ 0 });
    if( sizeof( l ) )
    {
      if( mask )
        l = ({ mask })+l;
      mask = Image.lay( l );
    }
  }

  right = frame->xsize()-right;
  if (mask != frame)
  {
    Image.Image i = mask->image();
    Image.Image m = mask->alpha();
    int x0 = -mask->xoffset();
    int y0 = -mask->yoffset();
    int x1 = frame->xsize()-1+x0;
    int y1 = frame->ysize()-1+y0;
    
    i = i->copy(x0,y0, x1,y1);
    if( m )
      m = m->copy(x0,y0, x1,y1);
    mask->set_image( i, m );
    mask = stretch_layer( mask, left, right, req_width );
  }
  if( frame != background )
    frame = stretch_layer( frame, left, right, req_width );
  array(Image.Layer) button_layers = ({
     Image.Layer( Image.Image(req_width, frame->ysize(), args->bg),
                  mask->alpha()->copy(0,0,req_width-1,frame->ysize()-1)),
  });


  if( args->extra_background_layers || background)
  {
    array l = ({ background });
    foreach( (args->extra_background_layers||"")/","-({""}), string q )
      l += ({ ll[q] });
    l-=({ 0 });
    foreach( l, object ll )
    {
      if( args->dim )
        ll->set_alpha_value( 0.3 );
      button_layers += ({ stretch_layer( ll, left, right, req_width ) });
    }
  }

  if( !noframe )
  {
    button_layers += ({ frame });
    frame->set_mode( "value" );
  }

  if( args->dim )
  {
    //  Adjust dimmed border intensity to the background
    int bg_value = Image.Color(@args->bg)->hsv()[2];
    int dim_high, dim_low;
    if (bg_value < 128) {
      dim_low = max(bg_value - 64, 0);
      dim_high = dim_low + 128;
    } else {
      dim_high = min(bg_value + 64, 255);
      dim_low = dim_high - 128;
    }
    frame->set_image(frame->image()->
                     modify_by_intensity( 1, 1, 1,
                                          ({ dim_low, dim_low, dim_low }),
                                          ({ dim_high, dim_high, dim_high })),
                     frame->alpha());
  }

  //  Draw icon.
  if (icon)
    button_layers += ({
      Image.Layer( ([
        "alpha_value":(args->dim ? 0.3 : 1.0),
        "image":icon->img,
        "alpha":icon->alpha,
        "xoffset":icn_x,
        "yoffset":icn_y
      ]) )});

  //  Draw text
  if(text_img)
  {
    float ta = args->txtalpha?args->txtalpha:1.0;
    button_layers +=
      ({
        Image.Layer(([
          "mode":args->txtmode,
          "image":text_img->color(0,0,0)->invert()->color(@args->txt),
          "alpha":(text_img*(args->dim?0.5*ta:ta)),
          "xoffset":txt_x,
          "yoffset":txt_y,
        ]))
     });
  }

  // 'plain' extra layers are added on top of everything else
  if( args->extra_layers )
  {
    array q = map(args->extra_layers/",",
                  lambda(string q) { return ll[q]; } )-({0});
    foreach( q, object ll )
    {
      if( args->dim )
        ll->set_alpha_value( 0.3 );
      button_layers += ({stretch_layer(ll,left,right,req_width)});
      button_layers[-1]->set_offset( 0,
                                     button_layers[0]->ysize()-
                                     button_layers[-1]->ysize() );
    }
  }

  button_layers  -= ({ 0 });
  // left layers are added to the left of the image, and the mask is
  // extended using their mask. There is no corresponding 'mask' layers
  // for these, but that is not a problem most of the time.
  if( args->extra_left_layers )
  {
    array l = ({ });
    foreach( args->extra_left_layers/",", string q )
      l += ({ ll[q] });
    l-=({ 0 });
    l->set_offset( 0, 0 );
    if( sizeof( l ) )
    {
      object q = Image.lay( l );
      foreach( button_layers, object b )
      {
        int x = b->xoffset();
        int y = b->yoffset();
        b->set_offset( x+q->xsize(), y );
      }
      q->set_offset( 0, button_layers[0]->ysize()-q->ysize() );
      button_layers += ({ q });
    }
  }

  // right layers are added to the right of the image, and the mask is
  // extended using their mask. There is no corresponding 'mask' layers
  // for these, but that is not a problem most of the time.
  if( args->extra_right_layers )
  {
    array l = ({ });
    foreach( args->extra_right_layers/",", string q )
      l += ({ ll[q] });
    l-=({ 0 });
    l->set_offset( 0, 0 );
    if( sizeof( l ) )
    {
      object q = Image.lay( l );
      q->set_offset( button_layers[0]->xsize()+
                     button_layers[0]->xoffset(),
                     button_layers[0]->ysize()-q->ysize());
      button_layers += ({ q });
    }
  }

//   if( !equal( args->pagebg, args->bg ) )
//   {
  // FIXME: fix transparency (somewhat)
  // this version totally destroys the alpha channel of the image,
  // but that's sort of the intention. The reason is that
  // the png images are generated without alpha.
  if (args->format == "png")
    return ({ Image.Layer(([ "fill":args->pagebg, ])) }) + button_layers;
  else
    return button_layers;
//   }
}


mixed tab(mapping args)
{
    mapping gbutton_args = args;
	

    string fimage;
    if ( !stringp(args->frame_image) ) {
	fimage = Stdio.read_file("tabframe.xcf");
	gbutton_args["frame-image"] = fimage;
    }
    else {
	object fimg = _FILEPATH->path_to_object(args->frame_image);
	fimage = fimg->get_content();
    }
    

    array(Image.Layer) button_layers;
    if( args->selected  ) {
	//add_layers( gbutton_args, "selected" );
	gbutton_args->bg = Colors.parse_color(args->selcolor || "white");
	gbutton_args->txt = Colors.parse_color(args->seltextcolor || "black");
	gbutton_args->txtmode = (args->textmode ||"normal");
	button_layers = draw_button(gbutton_args, "Hello");
    } else {
	//add_layers( gbutton_args, "unselected" );
	gbutton_args->bg =  Colors.parse_color(args->dimcolor || "#003366");
	gbutton_args->txt = Colors.parse_color(args->textcolor || "white");
	gbutton_args->txtmode = (args->textmode ||"normal");
	button_layers = draw_button(gbutton_args, args->text);
    }
    m_delete(gbutton_args, "selected");
    m_delete(gbutton_args, "dimcolor");
    m_delete(gbutton_args, "seltextcolor");
    m_delete(gbutton_args, "selcolor");
    m_delete(gbutton_args, "result");
    return button_layers;
}

array(string) execute(mapping args)
{
    array layers = tab(args);
    object img = Image.lay( layers );
    string str = Image.PNG->encode(img->image());
    return ({ str, "image/gif" });
}

string get_identifier() { return "buttons"; }

#if 0
void main(int argc, array argv)
{

    object img = Image.lay( layers );
    Stdio.write_file("test.jpg", Image.GIF->encode(img->image()));
}
#endif
