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
 * $Id: tar.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: tar.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module.pike";

//! This is the tar module. It is able to create a string-archive of
//! all tared files.

#include <macros.h>
#include <database.h>
#include <classes.h>

//#define TAR_DEBUG 1

#ifdef TAR_DEBUG
#define LOG_TAR(s, args...) werror("tar: "+s+"\n", args)
#else
#define LOG_TAR(s, args...)
#endif

#define BLOCKSIZE 512

/**
 * Convert an integer value to oct.
 *  
 * @param int val - the value to convert
 * @param int size - the size of the resulting buffer
 * @return the resulting string buffer
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static string to_oct(int val, int size)
{
    string v = (string) val;
    string oct = "";
    int i;

# define MAX_OCTAL_VAL_WITH_DIGITS(digits) (1 << ((digits) * 3) - 1)
    
    for ( i = 0; i < size; i++ ) oct += " ";
    
    if ( val <= MAX_OCTAL_VAL_WITH_DIGITS(size-1) )
	oct[--i] = '\0';
    
    while ( i >= 0 && val != 0 ) {
	oct[--i] = '0' + (int)(val&7);
	val >>=3;
    }

    while ( i!=0 )
	oct[--i] = '0';
    return oct;
}

static private string header;

/**
 * Copy a source string to the header at position 'pos'.
 *  
 * @param string source - source string to copy.
 * @param int pos - the position to copy it in 'header'.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void buffer_copy(string source, int pos)
{
    for ( int i = 0; i < strlen(source); i++ )
	header[pos+i] = source[i];
}


/**
 * Create a header in the tarfile with name 'fname' and content 'content'.
 *  
 * @param fname - the filename to store.
 * @param content - the content of the file.
 * @return the tar header for the filename.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static string tar_header(string fname, string content)
{
    int  i, l;
    string name, prefix;
    
    fname = replace
	(fname, 
	 ({ "ä", "ö", "ü", "Ä", "Ö", "Ü", "ß", "<", ">", "?", " ", "'" }),
	 ({ "\344", "\366", "\374", "\304", "\326", "\334", "\337", 
		"\74", "\76", "\77", "\40", "\47" }));

    if ( !stringp(content) )
      l = 0;
    else
      l = strlen(content);


    if ( strlen(fname) > 99 ) {
      name = basename(fname);
      prefix = dirname(fname);
    }
    else {
      name = fname;
      prefix = "\0";
    }
    if ( strlen(name) > 99 )
	error("Cannot store names with more than 99 bytes: "+name+"\n");
    if ( strlen(prefix) > 154 )
	error("Cannot store files with prefix more than 154 chars.");

    header = "\0" * BLOCKSIZE;

    buffer_copy(name,  0);
    buffer_copy("0100664",  100);
    buffer_copy("0000767",  108);
    buffer_copy("0000767",  116);
    buffer_copy(to_oct(l, 12),  124);
    buffer_copy(to_oct(time(), 12),  136);
    int chksum = 7*32; // the checksum field is counted as ' '
    buffer_copy("ustar  ",  257);
    buffer_copy("steam",  265);
    buffer_copy("steam",  297);
    buffer_copy(" 0",  155);
    
    buffer_copy(prefix, 345);
    
    for ( i = 0; i < BLOCKSIZE; i++ )
      chksum += (0xff & header[i]);
    
    buffer_copy(to_oct(chksum, 7),  148);
    
    return header;
}

/**
 * Tar the content of the file 'fname'. Tars both header and content.
 *  
 * @param string fname - the filename to tar.
 * @param string content - the content of the file.
 * @return the tared string.
 */
string tar_content(string fname, string content)
{
    string buf;
    if ( !stringp(fname) || fname== "" ) {
	FATAL("Empty file name !");
	return "";
    }
    LOG("tar_content("+fname+", "+strlen(content)+" bytes)\n");
    if ( !stringp(content) || strlen(content) == 0  ) 
	return tar_header(fname, content);

    buf = tar_header(fname, content);
    buf += content;
    int rest = (strlen(content) % BLOCKSIZE);
    if ( rest > 0 ) { // does not fit into a single buffer
	rest = BLOCKSIZE - rest;
	string b = "\0" * rest;
	buf += b;
    }
    return buf;
}

/**
 * Create an end header for the tarfile.
 *  
 * @return the end header.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string end_header()
{
    return "\0" * BLOCKSIZE; 
}

/**
 * Create an empty tarfile header.
 *  
 * @return an empty tarfile header.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see tar_header
 */
string empty_header()
{
    return tar_header("", "");
}

/**
 * Create a tarfile with an array of given steam objects. This
 * tars there identifiers and call the content functions.
 *  
 * @param array(object) arr - array of documents to be tared.
 * @return the tarfile.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string tar_objects(array(object) arr)
{
    string tar = "";
    foreach(arr, object obj) {
	tar += tar_content(obj->get_identifier(), obj->get_content());
    }
    tar += end_header(); // empty header at the end
    return tar;
}

object open_file(string fname, mixed mode)
{
    return ((program)"/kernel/DocFile")(OBJ(fname), mode);
}

class steamfs {
  inherit Filesystem.Base;
  object open(string fname, string mode)
  {
    LOG_TAR("steamfs:open(%s)", fname);
    object file = find_object(fname);
    //return Stdio.FakeFile(file->get_content(), mode);
    return open_file(fname, mode);
  }
  array(string) get_dir(string dirname) {
    array(string) files = ({ });

    object cont = find_object(dirname);
    array(object) dir = cont->get_inventory();
    foreach(dir, object o) {
      if ( o->get_object_class() & CLASS_CONTAINER )
	files += ({ o->get_identifier() + "/" });
      else
	files += ({ o->get_identifier()  });
    }
    return files;
  }
  array(object) get_files(string dirname) {
    object cont = find_object(dirname);
    return cont->get_inventory();
  }
}

static array unpack_directory(string fs, string dirname, void|object contEnv)
{
  array(string) files;
  array(object) created = ({ });
  object fsys = TarFile(fs);

  LOG_TAR("tar: unpack_directory(%s)", dirname);
  files = fsys->get_dir(dirname);
  foreach(files, string fname) {
    //object file = TarFile(fs)->open(fname, "r");
    object file = fsys->open(fname, "r");
    if ( !objectp(file) )
	steam_error("Failed to open: " + dirname + fname);

    array(object) contfiles;
    object cont, doc;

    if ( file->isdir() ) // container ?
    {
        cont = get_factory(CLASS_CONTAINER)->execute( ([ "name": 
							 basename(fname), ]) );
        contfiles = unpack_directory(fs, fname, cont);
	foreach(contfiles, object dirfile) 
          dirfile->move(cont);
	created += ({ cont });
    }
    else // ansonsten: File
    {
        fname = basename(fname);
	LOG_TAR("tar: file(%s)", fname);
        doc = get_factory(CLASS_DOCUMENT)->execute( (["name":fname, ]) ); 
	if ( objectp(contEnv) )
	  doc->move(contEnv); // move before setting ocntent
	doc->set_content( file->read() );
        created += ({ doc });
        LOG_TAR("tar: file(%s) has %d bytes", fname, doc->get_content_size());
    }
    file->close();
    
  }
  return created;
}

array unpack(string|object fname)
{
    if ( objectp(fname) )
	fname = get_module("filepath:tree")->object_to_filename(fname);
    LOG_TAR("tar: unpack(%s)", fname);
    array result = unpack_directory(fname, "");
    return result;
}

class _Tar  // filesystem
{
  Stdio.File fd;
  string filename;

  class ReadFile
  {
    inherit "/kernel/DocFile";

    static private int start, pos, len;
    static string _type;

    static string _sprintf(int t)
    {
      return t=='O' && sprintf("Filesystem.Tar.ReadFile(%d, %d /* pos = %d */)",
			       start, len, pos);
    }

    int seek(int p)
    {
      if(p<0)
        if((p += len)<0)
          p = 0;
      if(p>=len) {
        p = len-1;
        if (!len) p = 0;
      }
      return ::seek((pos = p)+start);
    }

    string read(int|void n)
    {
      if(!query_num_arg() || n>len-pos)
        n = len-pos;
      pos += n;
      return ::read(n);
    }

    void create(int p, int l, string type)
    {
      ::create(fd->get_document(), "r");
      start = p;
      len = l;
      _type = type;
      seek(0);
    }
    int isdir() 
    { 
      return !stringp(_type) || _type == "dir";
    }
  }

  class Record
  {
    inherit Filesystem.Stat;

    constant RECORDSIZE = 512;
    constant NAMSIZ = 100;
    constant TUNMLEN = 32;
    constant TGNMLEN = 32;
    constant SPARSE_EXT_HDR = 21;
    constant SPARSE_IN_HDR = 4;

    string arch_name;

    int linkflag;
    string arch_linkname;
    string magic;
    int devmajor;
    int devminor;
    int chksum;
    string type;

    int pos;
    int pseudo;

    // Header description:
    //
    // Fieldno  Offset  len     Description
    // 
    // 0        0       100     Filename
    // 1        100     8       Mode (octal)
    // 2        108     8       uid (octal)
    // 3        116     8       gid (octal)
    // 4        124     12      size (octal)
    // 5        136     12      mtime (octal)
    // 6        148     8       chksum (octal)
    // 7        156     1       linkflag
    // 8        157     100     linkname
    // 9        257     8       magic
    // 10       265     32                              (USTAR) uname
    // 11       297     32                              (USTAR) gname
    // 12       329     8       devmajor (octal)
    // 13       337     8       devminor (octal)
    // 14       345     167                             (USTAR) Long path
    //
    // magic can be any of:
    //   "ustar\0""00"  POSIX ustar (Version 0?).
    //   "ustar  \0"    GNU tar (POSIX draft)

    void create(void|string s, void|int _pos)
    {
      if(!s)
	{
	  pseudo = 1;
	  return;
	}

      pos = _pos;
      array a = array_sscanf(s,
                             "%"+((string)NAMSIZ)+"s%8s%8s%8s%12s%12s%8s"
                             "%c%"+((string)NAMSIZ)+"s%8s"
                             "%"+((string)TUNMLEN)+"s"
                             "%"+((string)TGNMLEN)+"s%8s%8s%167s");
      sscanf(a[0], "%s%*[\0]", arch_name);
      sscanf(a[1], "%o", mode);
      sscanf(a[2], "%o", uid);
      sscanf(a[3], "%o", gid);
      sscanf(a[4], "%o", size);
      sscanf(a[5], "%o", mtime);
      sscanf(a[6], "%o", chksum);
      linkflag = a[7];
      sscanf(a[8], "%s%*[\0]", arch_linkname);
      sscanf(a[9], "%s%*[\0]", magic);

      if((magic=="ustar  ") || (magic == "ustar"))
	{
	  // GNU ustar or POSIX ustar
	  sscanf(a[10], "%s\0", uname);
	  sscanf(a[11], "%s\0", gname);
	  if (a[9] == "ustar\0""00") {
	    // POSIX ustar        (Version 0?)
	    string long_path = "";
	    sscanf(a[14], "%s\0", long_path);
	    if (sizeof(long_path)) {
	      arch_name = long_path + "/" + arch_name;
	    }
	  } else if (arch_name == "././@LongLink") {
	    // GNU tar
	    // FIXME: Data contains full filename of next record.
	  }
	}
      else
        uname = gname = 0;

      sscanf(a[12], "%o", devmajor);
      sscanf(a[13], "%o", devminor);

      fullpath = combine_path_unix("/", arch_name);
      name = (fullpath/"/")[-1];
      atime = ctime = mtime;

      type =
      ([  0:"reg",
	  '0':"reg",
	  '1':0, // hard link
	  '2':"lnk",
	  '3':"chr",
	  '4':"blk",
	  '5':"dir",
	  '6':"fifo",
	  '7':0 // contigous
      ])[linkflag] || "reg";
      set_type(type);
    }

    object open(string mode)
    {
      if(mode!="r")
        error("Can only read right now.\n");
      return ReadFile(pos, size, type);
    }
  };

  array(Record) entries = ({});
  array filenames;
  mapping filename_to_entry;

  void mkdirnode(string what, Record from, object parent)
  {
    Record r = Record();

    if(what=="") what = "/";

    r->fullpath = what;
    r->name = (what/"/")[-1];

    r->mode = 0755|((from->mode&020)?020:0)|((from->mode&02)?02:0);
    r->set_type("dir");
    r->uid = 0;
    r->gid = 0;
    r->size = 0;
    r->atime = r->ctime = r->mtime = from->mtime;
    r->filesystem = parent;

    filename_to_entry[what] = r;
  }

  void create(Stdio.File fd, string filename, object parent)
  {
    this_program::filename = filename;
    // read all entries

    this_program::fd = fd;
    int pos = 0; // fd is at position 0 here
    for(;;)
      {
	Record r;
	string s = this_program::fd->read(512);

	if(s=="" || strlen(s)<512 || sscanf(s, "%*[\0]%*2s")==1)
	  break;

	r = Record(s, pos+512);
	r->filesystem = parent;

	if(r->arch_name!="")  // valid file?
	  entries += ({ r });

	pos += 512 + r->size;
	if(pos%512)
	  pos += 512 - (pos%512);
	this_program::fd->seek(pos);
      }

    filename_to_entry = mkmapping(entries->fullpath, entries);

    // create missing dirnodes

    array last = ({});
    foreach(entries, Record r)
      {
	array path = r->fullpath/"/";
	if(path[..sizeof(path)-2]==last) continue; // same dir
	last = path[..sizeof(path)-2];

	for(int i = 0; i<sizeof(last); i++)
	  if(!filename_to_entry[last[..i]*"/"])
	    mkdirnode(last[..i]*"/", r, parent);
      }

    filenames = indices(filename_to_entry);
  }

  string _sprintf(int t)
  {
    return t=='O' && sprintf("_Tar(/* filename=%O */)", filename);
  }
};

class _TarFS
{
  inherit Filesystem.System;

  _Tar tar;

  static Stdio.File fd;    // tar file object
  //not used; it's present in tar->filename, though /jhs 2001-01-20
  //static string filename;  // tar filename in parent filesystem

  void create(void|_Tar _tar,
              void|string _wd, void|string _root,
              void|Filesystem.Base _parent)
  {
    tar = _tar;

    sscanf(reverse(_wd), "%*[\\/]%s", wd);
    wd = reverse(wd);
    if(wd=="")
      wd = "/";

    sscanf(_root, "%*[/]%s", root);
    parent = _parent;
  }

  string _sprintf(int t)
  {
    return  t=='O' && sprintf("_TarFS(/* root=%O, wd=%O */)", root, wd);
  }

  Filesystem.Stat stat(string file, void|int lstat)
  {
    file = combine_path_unix(wd, file);
    return tar->filename_to_entry[root+file];
  }

  array(string) get_dir(void|string directory, void|string|array globs)
  {
    directory = combine_path_unix(wd, (directory||""), "");

    array f = glob(root+directory+"?*", tar->filenames);
    f -= glob(root+directory+"*/*", f); // stay here

    return f;
  }

  Filesystem.Base cd(string directory)
  {
    Filesystem.Stat st = stat(directory);
    if(!st) return 0;
    if(st->isdir()) // stay in this filesystem
      {
	object new = _TarFS(tar, st->fullpath, root, parent);
	return new;
      }
    return st->cd(); // try something else
  }

  Stdio.File open(string filename, string mode)
  {
    LOG_TAR("fS:open(%s)",filename);
    filename = combine_path_unix(wd, filename);
    return tar->filename_to_entry[root+filename] &&
      tar->filename_to_entry[root+filename]->open(mode);
  }

  int access(string filename, string mode)
  {
    return 1; // sure
  }

  int rm(string filename)
  {
  }

  void chmod(string filename, int|string mode)
  {
  }

  void chown(string filename, int|object owner, int|object group)
  {
  }
}

class TarFile {
  inherit _TarFS;
  
  void create(string filename)
  {
    object parent = steamfs();
    object fd = parent->open(filename, "r");
    _Tar tar = _Tar(fd, filename, this_object());
    _TarFS::create(tar, "/", "", parent);
  }
  string _sprintf(int t) {
      return  t=='O' && sprintf("TarFile(/* root=%O, wd=%O */)", root, wd);
  } 
}

string get_identifier() { return "tar"; }


