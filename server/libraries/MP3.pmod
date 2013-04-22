#pike __REAL_VERSION__

#! /usr/bin/env pike
// $Id: MP3.pmod,v 1.2 2009/08/07 15:22:37 nicke Exp $

// Based on MP3 parser in Icecast module for Roxen Webserver

//! A MP3 file parser with additional features:
//!  - allows adding metadat info for streaming
//!  - supports ID3 tags

//#define PARSER_MP3_DEBUG
#if 1
#define DEBUG(X, Y ...) werror("Parser.MP3: " + X, Y)
#else
#define DEBUG(X, Y ...)
#endif



#define BSIZE 8192

class File {

  private Buffer buffer;
  private int metainterval;
  private string metadata;
  private mapping peekdata;
  private int start = 1;
  private int nochk;

  void create(Stdio.File|string fd, int|void nocheck) {
    nochk = nocheck;
    buffer = Buffer(fd);
    if(!nocheck)
      if(!mappingp(peekdata = get_frame()))
        error("No MP3 file.\n");
  }

  string _sprintf() {
    return buffer->fd ? 
      sprintf("Parser.MP3.File(\"%O\",%O)", buffer->fd, nochk) :
      sprintf("Parser.MP3.File(string(%d),%O)", sizeof(buffer->origbuf), nochk);
  }

  private int rate_of(int r) {
    switch(r)
    {
      case 0: return 44100;
      case 1: return 48000;
      case 2: return 32000;
      default:return 44100;
    }
  }

  static array(array(int)) bitrates_map =
  ({
    ({0,32,64,96,128,160,192,224,256,288,320,352,384,416,448}),
    ({0,32,48,56,64,80,96,112,128,160,192,224,256,320,384}),
    ({0,32,40,48,56,64,80,96,112,128,160,192,224,256,320}),
  });


  //! Gets next frame from file
  mapping|int get_frame() { 
    string data;
    int bitrate;
    int trate = 0;
    int patt = 0;
    int prot = 0;
    int by, p=0, sw=0;
    mapping rv;

    if(mappingp(peekdata)) {
      rv = peekdata;
      peekdata = 0;
      return rv;
    }

#if 1
    if(start) {
      skip_id3v2();
      start = 0;
    }
#endif

    while( (by = buffer->getbytes( 1  )) > 0  ) {
      DEBUG("get_frame: getbytes = %O\n", by);
      patt <<= 8;
      patt |= by;
      p++;
      if( (patt & 0xfff0) == 0xfff0 )
      {
	int srate, layer, ID, pad, blen;
	int header = ((patt&0xffff)<<16);
	if( (by = buffer->getbytes( 2 )) < 0 )
	  break;
	header |= by;

        int getbits(int n) {
          int res = 0;
    
          while( n-- >= 0 ) {
            res <<= 1;
            if( header&(1<<31) )
              res |= 1;
            header<<=1;
          }
          return res;
        };

	string data = sprintf("%4c",header);
	patt=0;
	header <<= 12;
	ID = getbits(1); // version
	DEBUG("ID: %O\n", ID);
	if(!ID) /* not MPEG1 */
	  continue;
	layer = (4-getbits(2));

	//header<<=1; /* getbits(1, header); // error protection */
	prot = getbits(1);

	bitrate = getbits(4); 
	srate = getbits(2);
      
	if((layer>3) || (layer<2) ||  (bitrate>14) || (srate>2))
	  continue;
      
	pad = getbits(1);
	rv = ([ "private": getbits(1),
		"channel": getbits(2),
		"extension": getbits(2),
		"copyright": getbits(1),
		"original": getbits(1),
		"emphasis": getbits(2)
	      ]);
	bitrate = bitrates_map[ layer-1 ][ bitrate ] * 1000;
	srate = rate_of( srate );

	switch( layer )
	{
	  case 1:
	    blen = (int)(12 * bitrate / (float)srate + (pad?4:0))-4;
	    break;
	  case 2:
	  case 3:
	    blen = (int)(144 * bitrate / (float)srate + pad )-4;
	    break;
	}

	string q = buffer->getbytes( blen,1 );
	if(!q) {
	  DEBUG("get_frame: getbytes: %O\n", q);
	  return 0;
	}
	//return data + q;
	return ([ "data": data + q,
			"id": ID,
			"layer": layer,
			"bitrate": bitrate,
			"padding": pad,
			"sampling": srate,

		]) + rv;
      }
    }
    return 0;
  }

#if constant(Standards.ID3)
  //! Gets ID3 tags from file
  Standards.ID3.Tag|int get_id3() {

  }
#endif

  //! Gets current value of metainterval value
  int get_metaint() {
    return metainterval;
  }

  //! Sets a new metainterval value
  void set_metaint(int newmint) {
    metainterval = newmint;
  }

  //! Copy file with new values
  int save_file(string filename) {

  }

  private string|int encode_metadata(string mdata) {

  }

  //! Updates current metadata for streaming
  int(0..1) update_metadata(string mdata) {
    if(!metainterval)
      return 0;
    metadata = encode_metadata(mdata);
    return stringp(metadata);
  }

#if !constant(Standards.ID3hack)
  //! Skips ID3 version 2 tags at beginning of file
  int skip_id3v2() {
	string buf = buffer->peek(10);
	int nlen;
	if(buf[..2] == "ID3") {
	  nlen = ss2int( (array(int))buf[6..9] );
	  if(nlen)
	    buffer->getbytes(nlen + 10, 1);
	  while(buffer->peek(1) == "\0") {
	    //padding
	    buffer->getbytes(1, 1);
	    nlen++;
	  }
	} 
	DEBUG("skip_id3v2: %O\n", nlen ? nlen+10 : 0);
	return nlen ? nlen+10 : 0;
  }

  //! Decodes a synchsafe integer
  private int ss2int(array(int) bytes) {
    int res;
    DEBUG("ss2int: %O\n", bytes);
    foreach(bytes, int byte)
      res = res << 7 | byte;
    DEBUG("ss2int: ret=%O\n", res);
    return res;
  }
#endif
      
}

class Buffer {

  Stdio.File fd;
  /*private*/ string buffer;
  string origbuf;
  /*private*/ int bpos;

  void create(Stdio.File|string _fd) {
    if(objectp(_fd))
      fd = _fd;
    else {
      buffer = _fd;
      origbuf = _fd;
    }
  }

  //! Seeks the MP3 file
  int tell(int val) {
    if(fd) {
      int fpos = fd->tell();
      return fpos + (buffer ? (BSIZE - bpos) : 0) ;
    }
    //FIXME !
    error("No implemented for non Stdio.File source.\n");
  }

  //! Seeks the MP3 file
  int seek(int val) {
    if(fd) {
      buffer = 0;
      return fd->seek(val);
    }
    if(val > strlen(origbuf))
      return -1;
    buffer = origbuf;
  }
    
  //! Peeks data from buffer
  string|int peek(int n) {
    int bsav = bpos;
    string rv = getbytes(n, 1);
    if(stringp(rv)) {
      buffer = rv + buffer;
    }
    return rv;
  }

  //! Gets data from buffer
  string|int getbytes( int n, int|void s ) {
    DEBUG("getbytes: n: %d, s: %d\n", n, s);
    if( !buffer || !strlen(buffer) ) {
      if(!fd)
        return -1;
      bpos = 0;
      werror("Reading....");
      buffer = fd->read( BSIZE );
      werror("Done...\n");
    }
    if( !strlen(buffer) )
      return s?0:-1;
    if( s ) {
      if( strlen(buffer) - bpos > n ) {
	string d = buffer[bpos..bpos+n-1];
	buffer = buffer[bpos+n..];
	bpos=0;
	return d;
      }
      else {
        if(!fd)
          return 0;
	buffer = buffer[bpos..];
	bpos=0;
	werror("Reading....");
	string t = fd->read( BSIZE );
	werror("done\n");
	if( !t || !strlen(t) )
	  return -1;
	buffer+=t;
	return getbytes(n,1);
      }
    }
    int res=0;
    while( n-- >= 0 ) {
      res<<=8;
      res|=buffer[ bpos++ ];
      if( bpos == strlen(buffer) ) {
        if(!fd)
          return -1;
	bpos = 0;
	werror("Reading....");
	buffer = fd->read( BSIZE );
	werror("done\n");
	if( !buffer || !strlen( buffer ) )
	  return -1;
      }
    }
    return res;
  }

  string _sprintf() {
    return sprintf("Parser.MP3.Buffer(%s)", fd ? 
    	sprintf("%O", fd) : "string(" + sizeof(origbuf) + ")" );
  }
}
