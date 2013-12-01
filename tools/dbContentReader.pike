int documents;
int transfer;
int homeid;

void read_file_from_path(object db, string path, object file)
{
  array result = db->query(
	"select ob_id from ob_data where ob_attr='OBJ_PATH' AND ob_data='\""+
	path+"\"';");
  if (sizeof(result)>0) {
    int oid = result[0]["ob_id"];
    read_file_from_oid(db, oid, file);
  }
  else
    werror("Unable to retrieve file %s - path not found!\n", path);
}

void read_file_from_oid(object db, int oid, object file) 
{
  array doc_id = db->query(
         "select ob_data from ob_data where ob_attr='CONTENT_ID' AND ob_id='"+
	 oid+"';");
  if (sizeof(doc_id)>0) 
    read_file(db, (int)doc_id[0]["ob_data"], file);
  else
    werror("Unable to retrieve file %O - no Document!\n", oid);
}

string get_path(object db, int oid)
{
  array res = db->query("select ob_data from ob_data where ob_id="+
                        oid + " and ob_attr='OBJ_PATH'");
  if (sizeof(res)==0) {
    array env = db->query("select ob_data from ob_data where ob_id="+
                          oid + " and ob_attr='Environment'");
    if (sizeof(env)>0) {
      int envid;
      sscanf(env[0]["ob_data"], "%%%d", envid);
      if (envid==0) {
        array creator = db->query("select ob_data from ob_data where ob_id="+oid+" AND ob_attr='Creator'");
        if (sizeof(creator)>0) {
          int creatorid;
          sscanf(creator[0]["ob_data"], "%%%d", creatorid);
          array wr = db->query("select ob_data from ob_data where ob_id="+creatorid + " AND (ob_attr='GROUP_WORKROOM' OR ob_attr='USER_WORKROOM')");
          if (sizeof(wr)>0) 
            return "/home/"+get_name(db, creatorid);
        }
      }
      else if (envid==oid) {
        werror("Fatal error: Object %d is in itself!\n");
        return "/void/"+oid;
      }
      return get_path(db, envid) + "/" + get_name(db, oid);
    }
    return 0;
  }
  string p = "";
  sscanf(res[0]["ob_data"], "\"%s\"", p);
  return p;
}

string get_name(object db, int oid)
{
  array res = db->query("select ob_data from ob_data where ob_id='"+
                        oid + "' and ob_attr='identifier'");
  if (sizeof(res)==0) 
    return 0;
  string name = res[0]["ob_data"];
  int l = strlen(name);
  return l>0?name[1..l-2]:name;
}

void check_path(object db)
{
  int fixed = 0;
  int fail = 0;
  array objects = db->query("select ob_id from ob_class where ob_class like '/classes/Doc%'");
  if (sizeof(objects)>0) {
    write("Checking path for " + sizeof(objects) + " objects !\n");
    foreach(objects, mixed obj) {
      int oid = (int)obj["ob_id"];
      array res = db->query("select ob_data from ob_data where ob_id="+
                            oid + " and ob_attr='OBJ_PATH'");
      if (sizeof(res)==0) {
          string path = get_path(db, oid);
          if (stringp(path)) {
            db->query("update ob_data SET ob_data='\""+
                      db->quote(path)+"\"' where "+
                      "ob_id="+oid + " AND ob_attr='OBJ_PATH'");
            fixed++;
          }
          else
            fail++;
      }
    }
  }
  werror("Fixed %d Path (%d failed)\n", fixed, fail);
}

string content_id_to_path(int content_id) {
  if (content_id==0) return 0;
  string path = sprintf("%05d", content_id);
  int tmp_id = content_id >> 8;
  do {
    path = sprintf("%02x/",tmp_id&0xff)+path;
    tmp_id = tmp_id >> 8;
  } while (tmp_id>0);
  return path;
}



string mapPath(object db, int oid, string path) {
  string bname=basename(path);
  if ((string)((int)bname) == bname)
    path += ".content";
  return path;
}

string mapPathId(object db, int oid, string path) {
  array result = db->query(
	"select ob_data from ob_data where ob_attr='CONTENT_ID' AND ob_id="
	+oid);
  if (sizeof(result)>0) {
    int cid = (int)result[0]["ob_data"];
    return content_id_to_path(cid);
  }
  else {
    return 0;
  }
}


void read_files_from_path(object db, string path, mapping params, function mapPathFunction) 
{
  if (!params->output) {
    werror("You need to specify an output directory! (--output=)\n");
    return;
  }
  array result = db->query(
	"select ob_id, ob_data from ob_data where ob_attr='OBJ_PATH' AND "+
	"ob_data like '\""+path+"%';");
  if (sizeof(result)>0) {
    write("Fetching %d Document from Database in Path %s\n", sizeof(result),
          path);
    for (int i = 0; i < sizeof(result); i++) {
      int oid = (int)result[i]["ob_id"];
      string p = (string)result[i]["ob_data"];
      Stdio.mkdirhier(params->output);
      if (params->output[-1]!='/')
	params->output += "/";
      sscanf(p, "\"%s\"", p);
      p = p[1..];
      if (functionp(mapPathFunction)) {
        p = mapPathFunction(db, oid, p);
        if (p==0)
          continue;
      }

      string name = params->output + replace(p, "/versions", "__versions");
      name = replace(name, "/annotations", "__annotations");
      array directory = name / "/";

      array classResult = db->query(
	 "select ob_class, obversionof from ob_class where ob_id='"+ oid + "';");
      if (sizeof(classResult) > 0) {
	string obclass = classResult[0]["ob_class"];
	if (search(obclass, "/classes/Doc")==0 &&
	    classResult[0]["obversion"] == 0) 
	{
	  array doc_id = db->query(
            "select ob_data from ob_data where ob_attr='CONTENT_ID' AND ob_id='"+
	    oid+"';");
	  if (sizeof(doc_id)>0) {
	    if ( sizeof(directory) > 1 ) {
	      Stdio.mkdirhier(directory[..sizeof(directory)-2] * "/");
	    }
	    string bname = basename(name);
	    // only integer name in path
            write("Creating file " + name + "\n");
	    Stdio.File f = Stdio.File(name, "wct");
	    read_file(db, (int)doc_id[0]["ob_data"], f);
	    f->close();
	  }
	}
	else if (obclass == "/classes/Container" || obclass == "/classes/Room") 
        {
          if (mapPathFunction==mapPathId)
            continue;
	  Stdio.mkdirhier(name);
	}
      }
    }
  }
  else
    werror("Unable to retrieve files in %s - path not found!\n", path);
}

void read_file(object db, int id, object file) 
{
  Sql.sql_result odbData = db->big_query("select rec_data from doc_data "+
                                         "where doc_id="+id+" order by rec_order");

  documents++;
  while (array line = odbData->fetch_row()) {
    transfer+=strlen(line[0]);
    file->write(line[0]);
  }
}

void main(int argc, array args) {
  // params are --file= or --oid= or nothing and --output=<directory>
  // or --files=
  int tt = time();
  documents = 0;
  transfer = 0;
  mapping params = ([ ]);
  mapping mimetypes = ([
    "image/jpeg":"jpg",
    "image/gif":"gif",
    "application/msword": "doc",
    "application/pdf": "pdf",
    "audio/mpeg": "mp3",
    "image/bmp": "bmp",
    "text/plain": "text",
    "text/xml": "xml",
    "image/tiff": "tiff",
    "application/wnd.ms-powerpoint":"ppt",
    "application/x-shockwave-flash": "swf",
    "application/x-gzip":"zip",
    "application/x-gtar": "gtar",
    "application/x-tar": "tar",
    "audio/x-pn-realaudio": "ra",
    "audio/x-wav": "wav",
    "image/svg": "svg",
    "video/x-msvideo": "avi",
    "video/x-ms-wmv": "wmv",
    "application/vnd.ms-excel": "xls",
    "source/pike": "pike",
    "text/wiki": "wiki",
    "text/html": "html",
    "image/png": "png",
    "application/x-javascript": "js",
  ]);
  
  params["db"] = "mysql://steam:steam@localhost/steam";
  for(int i=1; i<argc;i++) {
    string type, val;
    if (sscanf(args[i], "--%s=%s", type, val) >=2)
      params[type] = val;
    else if (sscanf(args[i], "--%s", type)>=1)
      params[type] = 1;
  }
  
  Sql.Sql db = Sql.Sql(params->db);

  if (params["check-path"]) {
    check_path(db);
    return;
  }
  if (params["oid"]) {
    int oid;
    if (sscanf(params["oid"], "%d", oid)>0) {
      Stdio.File f = Stdio.File(oid+".file", "wct");
      read_file(db, oid, f);
      f->close();
      return;
    }
  }
  if (params["file"]) {
    Stdio.File f = Stdio.File(basename(params->file), "wct");
    read_file_from_path(db, params["file"], f);
    f->close();
    return;
  }
  if (params["files"]) {
    if (params["mode"]=="hash")
      read_files_from_path(db, params->files, params, mapPathId);
    else
      read_files_from_path(db, params->files, params, mapPath);
    transfer = transfer / (1024*1024);
    tt = max(time() - tt, 1);
    
    write("-- %d Documents in %d seconds, %d mb, %d mb/s", documents,
          tt, transfer, transfer/tt);
    return;
  }

  write("Getting DOC IDs ....\n");
  Sql.sql_result res = db->big_query("select distinct doc_id from doc_data");
  array(int) doc_ids = allocate(res->num_rows());
  for(int i=0;i<sizeof(doc_ids);i++)
    doc_ids[i]=(int)res->fetch_row()[0];
  write("Found %d Data entries in Database...\n", sizeof(doc_ids));

  res = db->big_query("select distinct ob_data from ob_data where ob_attr='CONTENT_ID';");
  mixed row;
  array content_ids = allocate(res->num_rows());
  write("Found %d Documents in Database ...\n", sizeof(content_ids));
  for (int i=0;i<res->num_rows();i++) {
    content_ids[i] = (int)res->fetch_row()[0];
  }
  array unallocated = doc_ids - content_ids;
  write("There are %d lost entries in the Database!\n", sizeof(unallocated));

  if (params->output) {
    write("Saving Files to %s\n", params->output);
    string dirname = params->output;
    Stdio.mkdirhier(dirname);
    if ( dirname[-1] != '/')
      dirname += "/";
    foreach(unallocated, int docid) {
      string fname = dirname + docid + ".file";
      Stdio.File f = Stdio.File(fname, "wct");
      read_file(db, docid, f);
      f->close();
      // try to get information
      Stdio.File outfile = Stdio.File("mimetype.out.tmp", "wct");
      int PCode = Process.create_process(
					 ({ "file", "-i", fname }),
					 ([ "env": getenv(),
					    "stdout" : outfile, ])
					 )->wait();
      outfile->close();
      string mimetype, ext;
      ext = "file";
      if (sscanf(Stdio.read_file("mimetype.out.tmp"),fname+": %s; %*s",mimetype) ||
	  sscanf(Stdio.read_file("mimetype.out.tmp"),fname+": %s, %*s",mimetype))
      {
	if (mimetypes[mimetype])
	  ext = mimetypes[mimetype];
	if (ext!="file") {
	  sscanf(fname, "%s.file", fname);
	  mv(fname+".file", fname + "." + ext);
	}
      }
    }
  }
    
}
