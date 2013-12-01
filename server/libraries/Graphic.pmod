#include <classes.h>
#include <attributes.h>
#include <macros.h>

string contentof(object obj)
{
  return obj->get_content();
}

mixed getAttribute(object img, string attr) 
{
  return img->query_attribute(attr);
}


array calculate_thumbnail_size ( int orig_width, int orig_height,
                                 int thumbnail_width, int thumbnail_height,
                                 void|bool ignore_aspect_ratio,
                                 void|bool dont_enlarge )
{
  if ( orig_width < 1 || orig_height < 1 ) return ({ 0, 0 });
  int w = thumbnail_width;
  int h = thumbnail_height;
  if ( dont_enlarge ) {
    if ( w > orig_width ) w = orig_width;
    if ( h > orig_height ) h = orig_height;
  }
  if ( w < 1 ) w = 0;
  if ( h < 1 ) h = 0;
  if ( w < 1 && h < 1 ) return ({ orig_width, orig_height });
  float aspect = (float)orig_width / (float)orig_height;
  if ( aspect == 0.0 ) aspect = 1.0;
  if ( w < 1 )
    w = (int)((float)h * aspect);
  else if ( h < 1 )
    h = (int)((float)w / aspect);
  else if ( !ignore_aspect_ratio ) {
    float scale_x = (float)w / (float)orig_width;
    float scale_y = (float)h / (float)orig_height;
    if ( scale_x < scale_y ) h = (int)((float)w / aspect);
    else w = (int)((float)h * aspect);
  }
  return ({ w, h });
}


/**
 * Returns a scaled image.
 * @see query_thumbnail
 *
 * @param img the image object of which to return the scaled content
 * @param xsize the desired width
 * @param ysize the desired height
 * @param maintain if true then maintain the aspect ratio when scaling
 * @param same_type if true then try to generate an image of the same type
 *   (jpeg, png, gif, bmp), otherwise jpeg is used by default
 * @return the scaled image data, or 0 if the image could not be scaled
 */
string get_thumbnail(object img, int xsize, int ysize, bool|void maintain,
                     bool|void same_type)
{
  /*
    object thumb;

    thumb= getAttribute(img, DOC_IMAGE_THUMBNAIL);
    if ( objectp(thumb) && getAttribute(thumb, DOC_IMAGE_SIZEX) == xsize )
      return thumb->get_content();
  */
    return query_thumbnail(img, xsize, ysize, maintain, same_type);
}


/**
 * Returns a scaled image.
 *
 * @param img the image object of which to return the scaled content
 * @param xsize the desired width
 * @param ysize the desired height
 * @param maintain if true then maintain the aspect ratio when scaling
 * @param same_type if true then try to generate an image of the same type
 *   (jpeg, png, gif, bmp), otherwise jpeg is used by default
 * @return the scaled image data, or 0 if the image could not be scaled
 */
string query_thumbnail(object img, int xsize, int ysize, bool|void maintain,
                       bool|void same_type)
{
    mapping  imageMap;
    Image.Image image;
 
    [imageMap, image ] = get_image(img);
    if ( !mappingp(imageMap) || !objectp(image) ) return 0;
    string mimetype;
    if ( same_type ) mimetype = imageMap->type;
    if ( !stringp(mimetype) || sizeof(mimetype) < 1 ) mimetype = "image/jpeg";

    float aspect = (float)image->xsize() / (float)image->ysize();
    if ( xsize < 1 && ysize < 1 )
      return img->get_content();
    else if ( xsize < 1 )
      xsize = (int)((float)ysize * aspect);
    else if ( ysize < 1 )
      ysize = (int)((float)xsize / aspect);
    else if ( maintain ) {  // both sizes specified but maintain aspect
      float scale_x = (float)xsize / (float)image->xsize();
      float scale_y = (float)ysize / (float)image->ysize();
      if ( scale_x < scale_y ) ysize = (int)((float)xsize / aspect);
      else xsize = (int)((float)ysize * aspect);
    }

    object new_image = image->scale(xsize, ysize);
    object alpha;
    if ( objectp(imageMap->alpha) )
      alpha = imageMap->alpha->scale(xsize, ysize);
    destruct(image);

    string img_content;
    switch ( mimetype ) {
#if constant(Image.GIF)
      case "image/gif":
        if ( objectp(alpha) )
          img_content = Image.GIF.encode_trans( new_image, alpha );
        else
          img_content = Image.GIF.encode( new_image );
        break;
#endif
#if constant(Image.PNG)
      case "image/png":
        if ( objectp(alpha) )
          img_content = Image.PNG.encode( new_image, (["alpha":alpha]) );
        else
          img_content = Image.PNG.encode( new_image );
        break;
#endif
      case "image/bmp":
      case "image/x-MS-bmp":
        img_content = Image.BMP.encode( new_image );
        break;
      case "image/jpeg":
      default:  // use jpeg as default...
#if constant(Image.JPEG)
        img_content = Image.JPEG.encode( new_image );
        break;
#else
        destruct( new_image );
        if ( objectp(alpha) ) destruct( alpha );
        return 0;
#endif
    }

    destruct(new_image);
    if ( objectp(alpha) ) destruct( alpha );
    return img_content;
}

string get_image_data(object obj)
{
#if constant(Image.JPEG)
    if ( intp(getAttribute(obj, DOC_IMAGE_ROTATION)) &&
	 getAttribute(obj, DOC_IMAGE_ROTATION) > 0  ) 
    {
	Image.Image image = get_image(obj)[1];
	string str = Image.JPEG.encode(image);
	destruct(image);
	return str;
    }
#endif
    return contentof(obj);
}

mapping get_image_map ( object obj )
{
  string mimetype = getAttribute( obj, DOC_MIME_TYPE );
  switch ( mimetype ) {
#if constant(Image.GIF)
    case "image/gif":
      return Image.GIF.decode_map(contentof(obj));
#endif
#if constant(Image.JPEG)
    case "image/jpeg":
      return Image.JPEG._decode(contentof(obj));
#endif
#if constant(Image.PNG) && constant(Image.PNG._decode) 
    case "image/png": {
      mapping m = Image.PNG._decode(contentof(obj));
      // Image.PNG._decode() doesn't put the mimetype in "type", fix this:
      if ( mappingp(m) ) {
        m["color_type"] = m["type"];
        m["type"] = "image/png";
      }
      return m;
    }
#endif
    case "image/bmp":
      return Image.BMP._decode(contentof(obj));
    default:
      return Image.ANY._decode(contentof(obj));
  }
  return 0;
}

array get_image(object obj)
{
    mapping imageMap = get_image_map( obj );
    
    Image.Image image = imageMap->image;
    if ( intp(getAttribute(obj, DOC_IMAGE_ROTATION)) ) {
	image = image->rotate(getAttribute(obj, DOC_IMAGE_ROTATION));
	imageMap->xsize = image->xsize();
	imageMap->ysize = image->ysize();
    }

    return ({ imageMap, image });
}

#if constant(get_module) 
object this() { return get_module("thumbnails"); }
object get_object() { return get_module("thumbnails"); }
int get_object_id() { return 1; }
bool trust(object obj) { return true; }
#endif

string get_identifier() { return "Graphic Module"; }
