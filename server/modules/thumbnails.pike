inherit "/kernel/module";

import Graphic;

#include <macros.h>
#include <events.h>
#include <attributes.h>
#include <classes.h>
#include <database.h>

//#define THUMB_DEBUG

#ifdef THUMB_DEBUG
#define LOG_THUMB(s, args...) werror("thumbnails: "+s+"\n", args)
#else
#define LOG_THUMB(s, args...)
#endif

int max_thumbnail_pixels = 25000000;


string get_identifier() { return "thumbnails"; }


int get_max_thumbnail_pixels () {
  return max_thumbnail_pixels;
}


void set_max_thumbnail_pixels ( int max_nr_pixels ) {
  max_thumbnail_pixels = max_nr_pixels;
}


/**
 * Returns a scaled thumbnail of an image object. The thumbnail will be
 * automatically cached on the object, so that subsequent requests don't
 * have to scale the image each time. If both width and height are
 * specified, then the image will be scaled to fit within that size, but
 * maintaining the aspect ratio (unless explicitly disabled). If only width
 * or height is specified, then the other size will be determined to match
 * the aspect ratio. E.g.: when requesting a 50x100 thumbnail of a 200x200
 * image, then a 50x50 thumbnail will be returned. If the aspect ratio is
 * set to ignore, then a 50x100 (deformed) thumbnail will be returned.
 *
 * @see get_image
 * @see get_thumbnail
 * @see get_thumbnail_data
 * 
 * @param obj the image object of which to get a scaled thumbnail
 * @param vars a mapping which specifies how the image should be scaled:
 *   "width": desired width (in pixels) for the thumbnail
 *   "height": desired height (in pixels) for the thumbnail
 *   "ignore_aspect_ratio": if 1, then the image will be scaled exactly
 *     to the specified sizes, even if that violates it's original aspect
 *     ratio (thus deforming the image)
 *   "dont_enlarge": don't enlarge the image, return the original size if
 *     the requested size is larger
 * @result a steam document obejct representing the scaled thumbnail
 */
mixed get_image ( object obj, mapping vars ) {
  int width, height, ignore_aspect, dont_enlarge;
  if ( mappingp(vars) ) {
    if ( intp(vars["width"]) ) width = vars["width"];
    else if ( stringp(vars["width"]) ) sscanf( vars["width"], "%d", width );
    if ( intp(vars["height"]) ) height = vars["height"];
    else if ( stringp(vars["height"]) ) sscanf( vars["height"], "%d", height );
    if ( intp(vars["ignore_aspect_ratio"]) )
      ignore_aspect = vars["ignore_aspect_ratio"];
    else if ( stringp(vars["ignore_aspect_ratio"]) )
      ignore_aspect = Config.bool_value( vars["ignore_aspect_ratio"] );
    if ( intp(vars["dont_enlarge"]) )
      dont_enlarge = vars["dont_enlarge"];
    else if ( stringp(vars["dont_enlarge"]) )
      dont_enlarge = Config.bool_value( vars["dont_enlarge"] );
  }
  return low_get_thumbnail( obj, width, height, ignore_aspect, dont_enlarge,
                            false );
}


/**
 * Returns a scaled thumbnail of an image object. The thumbnail will be
 * automatically cached on the object, so that subsequent requests don't
 * have to scale the image each time. If both width and height are
 * specified, then the image will be scaled to fit within that size, but
 * maintaining the aspect ratio (unless explicitly disabled). If only width
 * or height is specified, then the other size will be determined to match
 * the aspect ratio. E.g.: when requesting a 50x100 thumbnail of a 200x200
 * image, then a 50x50 thumbnail will be returned. If the aspect ratio is
 * set to ignore, then a 50x100 (deformed) thumbnail will be returned.
 *
 * @see get_image
 * @see get_thumbnail
 * @see get_thumbnail_data
 * 
 * @param obj the image object of which to get a scaled thumbnail
 * @param vars a mapping which specifies how the image should be scaled:
 *   "width": desired width (in pixels) for the thumbnail
 *   "height": desired height (in pixels) for the thumbnail
 *   "ignore_aspect_ratio": if 1, then the image will be scaled exactly
 *     to the specified sizes, even if that violates it's original aspect
 *     ratio (thus deforming the image)
 *   "dont_enlarge": don't enlarge the image, return the original size if
 *     the requested size is larger
 * @result the result is a mapping with the following entries:
 *   "content": binary content of the image
 *   "contentsize": size (in bytes) of the binary image content
 *   "name": name of the image (OBJ_NAME)
 *   "id": object id of the image
 *   "width": (optional, only when available) image width in pixels
 *   "height": (optional, only when available) image height in pixels
 *   "mimetype": mimetype of the image document (DOC_MIME_TYPE)
 *   "timestamp": (unix) time when the image was last changed
 *     (DOC_LAST_MODIFIED)
 */
mixed get_image_data ( object obj, mapping vars ) {
  int width, height, ignore_aspect, dont_enlarge;
  if ( mappingp(vars) ) {
    if ( intp(vars["width"]) ) width = vars["width"];
    else if ( stringp(vars["width"]) ) sscanf( vars["width"], "%d", width );
    if ( intp(vars["height"]) ) height = vars["height"];
    else if ( stringp(vars["height"]) ) sscanf( vars["height"], "%d", height );
    if ( intp(vars["ignore_aspect_ratio"]) )
      ignore_aspect = vars["ignore_aspect_ratio"];
    else if ( stringp(vars["ignore_aspect_ratio"]) )
      ignore_aspect = Config.bool_value( vars["ignore_aspect_ratio"] );
    if ( intp(vars["dont_enlarge"]) )
      dont_enlarge = vars["dont_enlarge"];
    else if ( stringp(vars["dont_enlarge"]) )
      dont_enlarge = Config.bool_value( vars["dont_enlarge"] );
  }
  return low_get_thumbnail( obj, width, height, ignore_aspect, dont_enlarge,
                            true );
}


/**
 * Returns a scaled thumbnail of an image object. The thumbnail will be
 * automatically cached on the object, so that subsequent requests don't
 * have to scale the image each time. If both width and height are
 * specified, then the image will be scaled to fit within that size, but
 * maintaining the aspect ratio (unless explicitly disabled). If only width
 * or height is specified, then the other size will be determined to match
 * the aspect ratio. E.g.: when requesting a 50x100 thumbnail of a 200x200
 * image, then a 50x50 thumbnail will be returned. If the aspect ratio is
 * set to ignore, then a 50x100 (deformed) thumbnail will be returned.
 *
 * @see get_thumbnail
 * @see get_image
 * @see get_image_data
 * 
 * @param obj the image object of which to get a scaled thumbnail
 * @param width desired width (in pixels) for the thumbnail
 * @param height desired height (in pixels) for the thumbnail
 * @param ignore_aspect_ratio (optional) if 1, then the image will be scaled
 *   exactly to the specified sizes, even if that violates it's original aspect
 *   ratio (thus deforming the image)
 * @param dont_enlarge (optional) don't enlarge the image, return the original
 *   size if the requested size is larger
 * @result a steam document obejct representing the scaled thumbnail
 */
mixed get_thumbnail ( object obj, int width, int height,
                      void|bool ignore_aspect_ratio, void|bool dont_enlarge ) {
  return low_get_thumbnail( obj, width, height, ignore_aspect_ratio,
                            dont_enlarge, false );
}


/**
 * Returns a scaled thumbnail of an image object. The thumbnail will be
 * automatically cached on the object, so that subsequent requests don't
 * have to scale the image each time. If both width and height are
 * specified, then the image will be scaled to fit within that size, but
 * maintaining the aspect ratio (unless explicitly disabled). If only width
 * or height is specified, then the other size will be determined to match
 * the aspect ratio. E.g.: when requesting a 50x100 thumbnail of a 200x200
 * image, then a 50x50 thumbnail will be returned. If the aspect ratio is
 * set to ignore, then a 50x100 (deformed) thumbnail will be returned.
 *
 * @see get_thumbnail
 * @see get_image
 * @see get_image_data
 * 
 * @param obj the image object of which to get a scaled thumbnail
 * @param width desired width (in pixels) for the thumbnail
 * @param height desired height (in pixels) for the thumbnail
 * @param ignore_aspect_ratio (optional) if 1, then the image will be scaled
 *   exactly to the specified sizes, even if that violates it's original aspect
 *   ratio (thus deforming the image)
 * @param dont_enlarge (optional) don't enlarge the image, return the original
 *   size if the requested size is larger
 * @result the result is a mapping with the following entries:
 *   "content": binary content of the image
 *   "contentsize": size (in bytes) of the binary image content
 *   "name": name of the image (OBJ_NAME)
 *   "id": object id of the image
 *   "width": (optional, only when available) image width in pixels
 *   "height": (optional, only when available) image height in pixels
 *   "mimetype": mimetype of the image document (DOC_MIME_TYPE)
 *   "timestamp": (unix) time when the image was last changed
 *     (DOC_LAST_MODIFIED)
 */
mixed get_thumbnail_data ( object obj, int width, int height,
                           void|bool ignore_aspect_ratio,
                           void|bool dont_enlarge ) {
  return low_get_thumbnail( obj, width, height, ignore_aspect_ratio,
                            dont_enlarge, true );
}


static mixed low_get_thumbnail ( object obj, int width, int height,
                                 void|bool ignore_aspect_ratio,
                                 void|bool dont_enlarge,
                                 void|bool return_data ) {
  if ( !objectp(obj) )
    THROW( "Invalid object", E_ERROR );
  string mimetype = obj->query_attribute( DOC_MIME_TYPE );
  if ( !stringp(mimetype) || !has_prefix(mimetype, "image") )
    THROW( "Object is not an image", E_ERROR );

  if ( width < 1 && height < 1 ) {
    if ( return_data ) return image_data( obj );
    else return obj;
  }

  mapping image_map = Graphic.get_image_map( obj );
  if ( !mappingp(image_map) || !intp(image_map->xsize) ||
       !intp(image_map->ysize) || !stringp(image_map->type) )
    THROW( "Invalid image.", E_ERROR );
  int w, h;
  [ w, h ] = Graphic.calculate_thumbnail_size( image_map->xsize,
                                               image_map->ysize, width, height,
                                               ignore_aspect_ratio,
                                               dont_enlarge );
  if ( w < 1 || h < 1 )
    THROW( "Could not get image size.", E_ERROR );
  if ( w * h > max_thumbnail_pixels )
    THROW( sprintf("Maximum image size is %d pixels", max_thumbnail_pixels),
           E_ERROR );

  mapping thumbnails = get_thumbnails( obj );
  if ( !mappingp(thumbnails) ) thumbnails = ([ ]);
  mapping thumbnail = thumbnails[ sprintf("%dx%d", w, h) ];

  // if a matching thumbnail exists then return it:
  if ( mappingp(thumbnail) && objectp(thumbnail->image) &&
       thumbnail->x == w && thumbnail->y == h &&
       thumbnail->timestamp >= obj->query_attribute(DOC_LAST_MODIFIED) ) {
    LOG_THUMB( "%dx%d : %dx%d thumbnail found", width, height, w, h );
    if ( return_data ) return image_data( thumbnail->image, w, h );
    else return thumbnail->image;
  }

  // create and store a new thumbnail:
  thumbnail = ([ ]);
  thumbnails[ sprintf("%dx%d", w, h) ] = thumbnail;

  // try to call a thumbnail service asynchronously:
  string service;
  mixed params;
  object service_manager = get_module("ServiceManager");
  // try java jgraphic service:
  if ( service_manager->is_service("jgraphic") ) {
    service = "jgraphic";
    params = ([ "image":obj->get_content(), "width":w, "height":h,
                "maintainAspect":0 ]);
  }
  // try pike graphic service:
  else if ( service_manager->is_service("graphic") ) {
    service = "graphic";
    params = ({ obj, w, h, 0 });
  }
  if ( stringp(service) && !zero_type(params) ) {
    LOG_THUMB( "%dx%d : new %dx%d thumbnail from %s service", width, height,
               w, h, service );
    object async_res = service_manager->call_service_async( service, params );
    async_res->mimetype = image_map->type;
    async_res->userData = ([ "obj":obj, "x":w, "y":h,
                             "return_data":return_data ]);
    async_res->processFunc = thumb_async_callback;
    return async_res;
  }

  // if no fitting services are available, generate the thumbnail directly:
  string thumb_data = query_thumbnail( obj, w, h, 0, true );
  if ( stringp(thumb_data) ) {
    LOG_THUMB("%dx%d : new %dx%d thumbnail (no service)", width, height, w, h);
    object thumb = create_thumbnail( obj, w, h, thumb_data );
    if ( return_data && objectp(thumb) )
      return image_data( thumb, w, h, image_map->type );
    else
      return thumb;
  }

  LOG_THUMB( "failed to handle %dx%d request", width, height );
  return 0;
}


void delete_thumbnail ( object obj, int width, int height ) {
  mapping thumbnails = get_thumbnails( obj );
  if ( !mappingp(thumbnails) ) return;
  string key = sprintf( "%dx%d", width, height );
  if ( has_index( thumbnails, key ) ) {
    mapping thumbnail = thumbnails[ key ];
    m_delete( thumbnails, key );
    if ( objectp(thumbnail->image) )
      thumbnail->image->delete();
  }
}


mapping get_thumbnails ( object obj ) {
  return obj->query_attribute( DOC_THUMBNAILS );
}


void delete_thumbnails ( object obj ) {
  mapping thumbnails = get_thumbnails( obj );
  if ( !mappingp(thumbnails) ) return;
  obj->set_attribute( DOC_THUMBNAILS, 0 );
  foreach ( values(thumbnails), mapping thumbnail ) {
    if ( !mappingp(thumbnail) ) continue;
    if ( objectp(thumbnail->image) )
      thumbnail->image->delete();
  }
}


static mixed thumb_async_callback ( mixed result, mixed user_data ) {
  if ( !mappingp(user_data) )
    return result;
  object obj = user_data->obj;
  int width = user_data->x;
  int height = user_data->y;
  int return_data = user_data->return_data;
  if ( !stringp(result) || !objectp(obj) || !intp(width) || !intp(height) )
    return 0;
  object img = create_thumbnail( obj, width, height, result );
  if ( return_data ) return image_data( img, width, height );
  else return img;
}


static mapping image_data ( object obj, int|void width, int|void height,
                            string|void mimetype ) {
  mixed content = obj->get_content();
  mapping res = ([ "content":content, "contentsize":sizeof(content) ]);
  res["name"] = obj->query_attribute( OBJ_NAME );
  res["id"] = obj->get_object_id();
  if ( width ) res["width"] = width;
  if ( height ) res["height"] = height;
  if ( stringp(mimetype) && sizeof(mimetype) > 0 )
    res["mimetype"] = mimetype;
  else
  res["mimetype"] = obj->query_attribute( DOC_MIME_TYPE );
  res["timestamp"] = obj->query_attribute( DOC_LAST_MODIFIED );
  return res;
}


static object create_thumbnail ( object obj, int width, int height, string data ) {
  if ( !stringp(data) || sizeof(data) < 1 ) return 0;

  string mimetype = "image/jpeg";
  mapping image_map = Image.ANY._decode( data );
  if ( mappingp(image_map) && stringp(image_map->type) &&
       sizeof(image_map->type) > 0 )
    mimetype = image_map->type;
  string name = sprintf( "thumbnail_%dx%d", width, height );
  if ( mimetype == "image/jpeg" ) name += ".jpg";
  else {
    array parts = mimetype / "/";
    if ( sizeof(parts) > 1 ) name += "." + parts[-1];
  }

  object img = get_factory( CLASS_DOCUMENT )->execute( ([
                                      "name":name, "mimetype":mimetype ]) );
  if ( !objectp(img) ) return 0;
  img->set_acquire( obj );
  mapping thumbnails = get_thumbnails( obj );
  if ( !mappingp(thumbnails) ) thumbnails = ([ ]);
  mapping old_thumbnail = thumbnails[ sprintf("%dx%d", width, height) ];
  mapping thumbnail = ([ ]);
  img->set_content( data );
  thumbnail->image = img;
  thumbnail->timestamp = time();
  if ( !zero_type(image_map->xsize) && intp(image_map->xsize) )
    thumbnail->x = image_map->xsize;
  else
  thumbnail->x = width;
  if ( !zero_type(image_map->ysize) && intp(image_map->ysize) )
    thumbnail->y = image_map->ysize;
  else
  thumbnail->y = height;
  thumbnails[ sprintf("%dx%d", width, height) ] = thumbnail;
  // set data:
  seteuid( USER("root") );
  mixed err = catch {
    if ( mappingp(old_thumbnail) && objectp(old_thumbnail->image) )
      old_thumbnail->image->delete();
    obj->set_attribute( DOC_THUMBNAILS, thumbnails );
    obj->add_depending_object( img );
  };
  seteuid( 0 );
  return img;
}


/* DEPRECATED: this obviously hasn't been called for years now, otherwise the
     server log would be full of "Creating thumb for ..." messages.
     Anyway, the function probably didn't do anything in the first place
     because the mime type for images is "image/jpeg" not "img/jpeg" ;-)

mixed getAttribute(object obj, string key)
{
  return obj->query_attribute(key);
}

void load_module()
{
  add_global_event(EVENT_UPLOAD, create_thumb, PHASE_NOTIFY);
}

object create_thumb(int e, object img, mixed ... args)
{
  object obj;


  string mime = img->query_attribute(DOC_MIME_TYPE);
  if ( !stringp(mime) )
    steam_error("Invalid empty mimetype for %O", img->get_object());
  if ( search(img->query_attribute(DOC_MIME_TYPE), "img") == -1 )
    return 0;

  MESSAGE("Creating thumb for " + img->get_identifier());
 
  obj = img->query_attribute(DOC_IMAGE_THUMBNAIL);
  if ( objectp(obj) )
    obj->delete();
  if ( get_content_size() == 0 )
    return 0;
  
  object factory = _Server->get_factory(CLASS_DOCUMENT);
  object thumb = factory->execute( 
				  ([ "name": "THUMB_"+img->get_identifier(),
				     "acquire": img, 
				  ]) 
				  );
  thumb->set_attribute("thumb", "true");
  thumb->set_content(query_thumbnail(img, 80, 80, true));
  thumb->set_attribute(DOC_IMAGE_SIZEX, 80);
  thumb->set_attribute(DOC_IMAGE_SIZEY, 80);
  img->set_attribute(DOC_IMAGE_THUMBNAIL, thumb);
  return thumb;
}
*/


static void test_image ( string mimetype, int w, int h,
                         int thumb_w, int thumb_h,
                         int expected_w, int expected_h,
                         void|bool ignore_aspect, void|bool dont_enlarge ) {
  mixed err = catch {
    object doc_factory = get_factory( CLASS_DOCUMENT );
    string name = sprintf( "testimage_%dx%d", w, h );
    string thumb_size = sprintf( "%dx%d", thumb_w, thumb_h );
    if ( ignore_aspect ) thumb_size += "_NoAspect";
    if ( dont_enlarge ) thumb_size += "_DontEnlarge";
    string content;
    switch ( mimetype ) {
    case "image/jpeg" :
      name += ".jpg";
      content = Image.JPEG.encode( Image.filled_circle( w, h ) );
      break;
    case "image/png" :
      name += ".png";
      content = Image.PNG.encode( Image.filled_circle( w, h ) );
      break;
    case "image/gif" :
      name += ".gif";
      content = Image.GIF.encode( Image.filled_circle( w, h ) );
      break;
    case "image/bmp" :
      name += ".bmp";
      content = Image.BMP.encode( Image.filled_circle( w, h ) );
      break;
    }
    if ( !stringp(content) || sizeof(content) < 1 )
      THROW( "could not encode "+mimetype+" image data", E_ERROR );
    object img = doc_factory->execute( (["name":name, "mimetype":mimetype]) );
    if ( !objectp(img) ) THROW("could not create "+name+" document", E_ERROR);
    img->set_content( content );
    object thumb1 = get_thumbnail( img, thumb_w, thumb_h, ignore_aspect,
                                   dont_enlarge );
    object thumb2 = get_thumbnail( img, thumb_w, thumb_h, ignore_aspect,
                                   dont_enlarge );
    object thumb3 = get_image( img, ([ "width":thumb_w, "height":thumb_h,
                                       "ignore_aspect_ratio":ignore_aspect,
                                       "dont_enlarge":dont_enlarge ]) );
    mapping data1 = get_thumbnail_data( img, thumb_w, thumb_h, ignore_aspect,
                                   dont_enlarge );
    mapping data2 = get_image_data( img, ([ "width":thumb_w, "height":thumb_h,
                                       "ignore_aspect_ratio":ignore_aspect,
                                       "dont_enlarge":dont_enlarge ]) );
    if ( !objectp(thumb1) )
      Test.failed( thumb_size+" thumbnail creation for "+name );
    else {
      Test.test( thumb_size+" thumbnail storage for "+name, thumb1 == thumb2 );
      Test.test( thumb_size+" thumbnail by mapping for "+name,
                 thumb1 == thumb3 );
      Test.test( thumb_size+" thumbnail mimetype for "+name,
                 thumb1->query_attribute( DOC_MIME_TYPE ) == mimetype );
      mapping img_map = Graphic.get_image_map( thumb1 );
      if ( !mappingp(img_map) )
        Test.failed( thumb_size+" thumbnail size check for "+name,
                     "could not get image map" );
      else {
        if ( !has_index(img_map, "xsize") || !has_index(img_map, "ysize") )
          Test.failed( thumb_size+" thumbnail size check for "+name,
                       "image map doesn't contain xsize and ysize" );
        else
          Test.test( thumb_size+" thumbnail size check for "+name,
                     expected_w == img_map->xsize &&
                     expected_h == img_map->ysize,
                     sprintf("thumbnail is %dx%d, should be %dx%d",
                             img_map->xsize, img_map->ysize,
                             expected_w, expected_h) );
      }
    }
    if ( !mappingp(data1) )
      Test.failed( thumb_size+" thumbnail data for "+name );
    else {
      Test.test( thumb_size+" thumbnail data by mapping for "+name,
                 equal( data1, data2) );
      Test.test( thumb_size+" thumbnail image data for "+name,
                 stringp(data1->content) && sizeof(data1->content) > 0 );
    }
    img->delete();
    if ( objectp(img) && img->status() != PSTAT_DELETED )
      Test.failed( "deleting test image %s"+name );
    else if ( objectp(thumb1) && thumb1->status() != PSTAT_DELETED )
      Test.failed( "deleting test image deletes thumbnail, too" );
  };
  if ( err ) Test.failed( sprintf("creating %dx%d %s image", w, h, mimetype),
                          "%s", err[0] );
}


void test () {
  object doc_factory = get_factory( CLASS_DOCUMENT );
  if ( !objectp(doc_factory) ) {
    Test.failed( "thumbnail tests", "could not get document factory" );
    return;
  }
  test_image( "image/jpeg", 100, 100, 0, 0, 100, 100 );
  test_image( "image/jpeg", 100, 100, 50, 50, 50, 50 );
  test_image( "image/jpeg", 100, 50, 50, 50, 50, 25 );
  test_image( "image/jpeg", 50, 100, 50, 50, 25, 50 );
  test_image( "image/jpeg", 100, 50, 50, 50, 50, 50, true );
  test_image( "image/jpeg", 100, 50, 50, 0, 50, 25 );
  test_image( "image/jpeg", 100, 50, 0, 50, 100, 50 );
  test_image( "image/jpeg", 100, 50, 50, 0, 50, 25, true );
  test_image( "image/jpeg", 50, 100, 0, 50, 25, 50, true );
  test_image( "image/jpeg", 50, 50, 100, 100, 100, 100, false, false );
  test_image( "image/jpeg", 50, 50, 100, 100, 50, 50, false, true );

  test_image( "image/png", 100, 100, 50, 50, 50, 50 );
  test_image( "image/gif", 100, 100, 50, 50, 50, 50 );
}
