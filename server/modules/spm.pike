inherit "/kernel/module";
inherit "/base/xml_data";

import httplib;

#include <database.h>
#include <macros.h>
#include <attributes.h>
#include <classes.h>

//#define SPM_DEBUG 1

#ifdef SPM_DEBUG
#define LOG_SPM(s, args...) werror("spm: "+s+"\n", args)
#else
#define LOG_SPM(s, args...)
#endif

class spmAPI {
    array spm_install_package() { return ({ }); }
    void|array spm_upgrade_package() { } 
    string get_identifier() { return "spmAPI"; }
}

class SPMHtmlHandler {
  inherit Async.HtmlHandler;

  int doPing = 1;

  void create() {
    head = "<html><body><div id='setuptext'>Installation in Progress</div>"+
      "</body>";
    ::create(0);
    start_thread(ping_http);
  }
  
  void set_request(object request) {
    request->connection_timeout_delay = 18000;
    request->send_timeout_delay = 18000;    
    ::set_request(request);
    catch(request->attach_fd(0,0));
  }

  void ping_http() { 
    while ( doPing ) {
      output(".");
      sleep(10);
    }
  }

  void log(string str) { doPing = 0; output(str+"<br/>"); }
}

static mapping mLogs = ([ ]);
static object oHandler;
static mapping mSetups = ([ ]);

static void runtime_install() 
{
    // make sure package container is there
    object packages = OBJ("/packages");
    if ( !objectp(packages) ) {
	packages=get_factory(CLASS_CONTAINER)->execute((["name":"packages",]));
	packages->move(OBJ("/"));
    }
    // try to install stylesheets for container !
    object pxsl = OBJ("/stylesheets/spm.xsl");
    if ( objectp(pxsl) ) {
	packages->set_attribute("xsl:content", ([ GROUP("steam"): pxsl, ]));
    }
    do_set_attribute(OBJ_NAME, "SPM");
    this()->move(OBJ("/"));
}

static array install_spm_modules(array modules, object dest, mapping config)
{
    object module, modsrc;
    array installed = ({ });
    
    mapping packages = ([ ]);
    object packageSrc = dest->get_object_byname("package");
    if ( !objectp(packageSrc) ) {
	packageSrc = 
	    get_factory(CLASS_CONTAINER)->execute( ([ "name":"package" ]) );
	packageSrc->move(dest);
    }
    
    dest->set_acquire_attribute("xsl:content", 0);
    dest->set_attribute("xsl:content", 
		      ([ GROUP("steam"):OBJ("/stylesheets/content.xsl"), ]) );

    object image;
    foreach(modules, object component ) {
	if ( component->get_object_class() & CLASS_DOCLPC ) {
	    string name = component->get_identifier();
	    
	    object pmod = packageSrc->get_object_byname(name);
	    sscanf(name, "%s.%*s", name);
	    if ( !objectp(pmod) ) {
              mixed err;
              err = catch(module = component->execute( (["name": name, ]) ));
              if ( err ) {
                FATAL("failed to compile new instance - throwing");
                mixed cerr = component->get_errors() || ({ "No errors !" });
                spm_log(dest, "install.log", "Failed to compile %s:\n%s",
                        name, cerr*"\n");
                throw(err);
              }
              spm_log(dest, "install.log", 
                      "Installing new Module %s", name);
              packages[component] = module->this();
		
	    }
	    else {
		pmod->set_content(component->get_content());
		pmod->upgrade();
		module = pmod->provide_instance();
		module = module->get_object();
		packages[pmod] = module->this();
		spm_log(dest, "install.log", 
			"Updating code of previous module %O", pmod);
	    }

	    if ( !Program.implements(object_program(module), 
				     object_program(spmAPI())) )
	    {
		spm_log(dest, "install.log", 
		     "Module does not correctly implement the SPM module API",
                     pmod);
		steam_user_error("The Package component " + 
			  component->get_identifier() +
			  " does not correctly implement the SPM module API ");
	    }
	}
	else {
          object old = packageSrc->get_object_byname(
                          component->get_identifier() );
          if ( !objectp(old) ) {
            component->move( packageSrc );
          }
          else if ( old->get_object_class() & CLASS_DOCUMENT ) {
            old->set_content( component->get_content() );
            component = old;
          }

          if ( (component->get_object_class() & CLASS_DOCXSL) &&
               component->get_identifier() == "package.xsl" ) {
            // set stylesheet for package
            dest->set_attribute("xsl:content",
                                ([ GROUP("steam"): component ]));
            spm_log(dest, "install.log", 
                    "Setting attribute for package (package.xsl)");
          }
          else if ( (component->get_object_class() & CLASS_DOCUMENT) &&
                search(component->query_attribute(DOC_MIME_TYPE),"image")>=0 )
            image = component;
	}
    }
    
    foreach( indices(packages), modsrc ) {
	module = packages[modsrc];
	object pmod = dest->get_object_byname(module->get_identifier());
	if ( objectp(pmod) && _Server->is_registered_module(pmod)) {
	  MESSAGE("Upgrading installation (spm_upgrade_package())");
	  spm_log(dest, "install.log", 
		  "Upgrading installation (spm_upgrade_package())");
	  module->move(dest);
	  module->spm_upgrade_package();
	  module->set_attribute(PACKAGE_VERSION, config->version);
	  installed += ({ module });
	}
	else {
	  MESSAGE("New installation (spm_install_package())");
	  spm_log(dest, "install.log", 
		  "New Installation (spm_install_package())");
	  module->move(dest);
	  module->spm_install_package();
	  module->set_attribute(PACKAGE_VERSION, config->version);
	  MESSAGE("Registering package in database!");
	  _Database->register_module(module->get_identifier(), module);
	  installed += ({ module });
	}
	if ( objectp(image) ) {
	    module->set_acquire_attribute(OBJ_ICON, 0);
	    module->set_attribute(OBJ_ICON, image);
	}
	spm_log(dest, "install.log", 
		"Registered Module %s", module->get_identifier());
	MESSAGE("Registered %s Module !", module->get_identifier());
	modsrc->move(packageSrc);
    }
    if ( objectp(image) ) {
	dest->set_acquire_attribute(OBJ_ICON, 0);
	dest->set_attribute(OBJ_ICON, image);
    }
    return installed;
}

static array install_spm_files(array files, object dest, object spm) 
{
    array installed = ({ });
    foreach(files, object file) {
	object oldfile = dest->get_object_byname(file->get_identifier());
	//upgrade - previous version!
	if ( objectp(oldfile) ) {
	    spm_log(spm, "install.log",
		    "Upgrading file %s", oldfile->get_identifier());
	    if ( oldfile->get_object_class() & CLASS_DOCUMENT ) {
                oldfile->set_content(file->get_content());
		installed += ({ oldfile });
	    }
	    else if ( oldfile->get_object_class() & CLASS_CONTAINER ) {
	      installed += install_spm_files(file->get_inventory(),
					     oldfile, 
					     spm);
            }
	}
	else {
	    spm_log(spm, "install.log",
		    "Installing new file %s", file->get_identifier());
	    file->move(dest);
            // do not delete container later on
            if ( !(file->get_object_class() & CLASS_CONTAINER) )
              installed += ({ file });
        }
    }
    return installed;
}

static array install_spm_src(array files, object dest, object spm)
{
  return install_spm_files(files, dest, spm);
}

static mixed get_package_config(object node, string id) 
{
    object n = node->get_node("/package/"+id);
    if ( !objectp(n) )
	steam_user_error("Configuration failed: missing " + id);
    return n->data;
}

static mapping read_configuration(object configObj)
{
    mapping config = ([ ]);
    LOG_SPM("Parsing %O\n", configObj->get_content());
    object node = xmlDom.parse(configObj->get_content());
    config->author = get_package_config(node, "author");
    config->description = get_package_config(node, "description");
    config->version = get_package_config(node, "version");
    config->name = get_package_config(node, "name");
    config->category = get_package_config(node, "category") || "Misc";
    config->stability = get_package_config(node, "stability") || "stable";
    return config;
}

static object create_package_cont(mapping config, object dest)
{
    object package = dest->get_object_byname(config->name);
    if ( !objectp(package) ) {
      object factory = get_factory(CLASS_CONTAINER);
      package = factory->execute( ([ "name": config->name, ]) );
    }
    LOG_SPM("create_package_cont() Config is %O\n", config);
    package->set_attribute(PACKAGE_VERSION, config->version);
    package->set_attribute(PACKAGE_AUTHOR, config->author);
    package->set_attribute(PACKAGE_CATEGORY, config->category);
    package->set_attribute(PACKAGE_STABILITY, config->stability);
    package->set_attribute(OBJ_DESC, config->description);
    package->set_acquire_attribute("xsl:content", 0);
    return package;
}

object spm_get_logfile(object spm, string logname)
{
    object factory;
    object packageCont;

    if ( spm->get_object_class() & CLASS_CONTAINER )
	packageCont = spm;
    else
	packageCont = spm->get_environment();

    object logs = packageCont->get_object_byname("logs");
    if ( !objectp(logs) ) {
	factory = get_factory(CLASS_CONTAINER);
	logs = factory->execute( ([ "name": "logs", ]) );
	logs->move(packageCont);
    }
    object log = logs->get_object_byname(logname);
    if ( !objectp(log) ) {
	factory = get_factory(CLASS_DOCUMENT);
	log = factory->execute( (["name":logname, "mimetype":"text/html" ]) );
	log->move(logs);
    }
    return log;
}

void spm_log(object spm, string logname, string htmlMessage, mixed ... args) 
{
    htmlMessage = "<li>" + htmlMessage + "</li>\n";
    if ( objectp(oHandler) ) 
        oHandler->log(sprintf(htmlMessage, @args) + "\n");

    if ( mLogs[logname] ) {
	mLogs[logname]->write(sprintf(htmlMessage, @args) + "\n");
	return;
    }
    
    object log = spm_get_logfile(spm, logname);
    if ( objectp(log) ) {
	mLogs[logname] = log->get_content_file("w", ([]));
	MESSAGE("SPM: Using Logfile %O", mLogs[logname]->describe());
	mLogs[logname]->write("<html><body><ul>");
	mLogs[logname]->write(sprintf(htmlMessage, @args) + "\n");
    }    
    else {
      FATAL("Failed to find logfile %O for SPM:\n%O\n",
	    logname, sprintf(htmlMessage, @args));
	     
    }
}

string spm_read_log(object spm, string logname)
{
    if ( !objectp(spm) )
	return "** package not found (null) **";
    
    if ( objectp(mLogs[logname]) )
	mLogs[logname]->close();

    object log = spm_get_logfile(spm, logname);
    if ( !objectp(log) )
	return "** logfile " + logname + " not found ! ** ";
    object version = log;
    int i = log->query_attribute(DOC_VERSION);
    string html = "";
    while ( objectp(version) && i >= 0 ) {
	html += version->get_content() + "<hr />";
	version = version->query_attribute(OBJ_VERSIONOF);
	i--;
    }
    return html;
}

void uninstall_spm(object spm_cont)
{
  object cont = spm_cont;
  if ( objectp(cont) ) {
    foreach(cont->get_inventory(), object o) {
      if ( objectp(o) && o->get_object_class() & CLASS_MODULE ) {
        catch ( o->pck_uninstall() );
        o->delete();
      }
    }
    object user = this_user() || USER("root");
    cont->move(user->query_attribute(USER_TRASHBIN));
    array rootfiles = cont->query_attribute(SPM_FILES) || ({ });
    foreach(rootfiles, object rf) {
      rf->delete();
    }
    array pModules = cont->query_attribute(SPM_MODULES) || ({ });
    foreach (pModules, object mod) 
      mod->delete();
  }
}

mixed install_spm(object spm, object dest, void|bool manualSetup)
{
    object file;
    object setup;
    object packageCont;
    object packages = OBJ("/packages");
    bool delete_after_install = false;
    mixed result = 1;
    int tt = get_time_millis();
    int tt_unpack = 0;

    if ( !objectp(packages) )
	steam_user_error("Failed to find packages: corrupt steam installation!");

    MESSAGE("Destination of SPM Install is %O\n", _FILEPATH->object_to_filename(dest));
    array(object) files;
    if ( spm->get_object_class() & CLASS_CONTAINER )
      files = spm->get_inventory();
    else {
      files = get_module("tar")->unpack(spm);
      tt_unpack = get_time_millis() - tt;
      delete_after_install = true;
    }

    mapping config = ([ ]);
    int foundConfig = 0;
    foreach(files, file) {
	if ( file->get_identifier() == "package.xml" ) {
	    config = spm_check_configuration(file->get_content());
	    foundConfig = 1;
	}
        if ( file->get_identifier() == "setup.xml" ) 
          setup = file; // use setup after everything is installed
    }
    if ( !foundConfig ) {
      if ( delete_after_install )
        foreach ( files, file )
          file->delete();
      steam_user_error("SPM(%O): Configuration file 'package.xml' not found !",
		       spm->get_identifier());
    }

    packageCont = create_package_cont(config, packages);
    packageCont->move(packages);
    spm_log(packageCont, "install.log", 
	    "Unpacked SPM in %d ms.", tt_unpack);

    int last_tt = get_time_millis();
    object packageFile;
    array installFiles = ({ });
    foreach(files, file) {
	if ( file->get_object_class() & CLASS_CONTAINER ) {
	    switch ( file->get_identifier() ) {
	    case "package":
              packageFile = file;
              break;
	    case "files":
              array myfiles = install_spm_files(file->get_inventory(), 
                                                OBJ("/"),
                                                packageCont);
              installFiles += myfiles;
              packageCont->set_attribute(SPM_FILES, myfiles);
              break;
	    case "src":
              array srcfiles = install_spm_src(file->get_inventory(),
                                               packageCont, packageCont);
              installFiles += srcfiles;
              break;
	    }
	}
    }
    spm_log(packageCont, "install.log", 
	    "Installed files in %d ms.", get_time_millis() - last_tt);

    last_tt = get_time_millis();
    if ( !(result=setup_package(dest, setup, installFiles)) )
      steam_error("Failed to setup package !");
    if ( !manualSetup ) {
      // if manual setup is not selected, then install all commands
      foreach(indices(result), object setupObj) {
	  spm_execute_commands(setupObj, result[setupObj]);
      }
    }
    spm_log(packageCont, "install.log", 
	    "Setup SPM in %d ms.", get_time_millis() - last_tt);
    last_tt = get_time_millis();

    if ( objectp(packageFile) ) {
      array modules = install_spm_modules(packageFile->get_inventory(), 
					  packageCont, config) || ({ });
      packageCont->set_attribute(SPM_MODULES, modules);
      installFiles += modules;
    }
    // delete temporary files:
    if ( delete_after_install ) {
      array delete_files = files - installFiles;
      foreach ( delete_files, file ) {
        file->delete();
      }
    }
    spm_log(packageCont, "install.log", 
	    "Setup Modules in %d ms.", get_time_millis() - last_tt);
    spm_log(packageCont, "install.log", 
	    "Installation completed in %d ms.", get_time_millis() - tt);

    // closing log files
    foreach(values(mLogs), object log) {
      log->write("\n</ul></body></html>\n");
      log->close();
      MESSAGE("Logfile %O with %d bytes", 
	      _FILEPATH->object_to_filename(log->get_document()), 
	      log->_sizeof());
    }

    return result;
}

static int access_to_int(string atype) 
{
  if ( !stringp(atype) )
    return 0;
  array accessDef = get_module("security")->get_sanction_strings();
  array accessVal = atype/",";
  int access = 0;
  foreach ( accessVal, string a ) {
    a = String.trim_all_whites(a);
    if ( a == "" ) 
      continue;
    int i = search(accessDef,a);
    if ( i == -1 )
      steam_error("Failed to set access for unknown type in %s", atype);
    access |= (1<<i);
  }
  return access;
}

static array setup_access(object obj, object access)
{
  array commands = ({ });
  if ( !objectp(access) )
    return commands;

  if ( !stringp(access->attributes->acquire) )
    steam_error("Unable to setup access, acquire not set for %s",
                access->get_xml());
  
  if ( access->attributes->acquire == "yes" ) 
    commands += spm_cmd(obj, "acquire", obj->get_environment);
  else
    commands += spm_cmd(obj, "acquire", 0);
    
  foreach(access->get_nodes("permit"), object permit) {
    int accessBit = access_to_int(permit->attributes->type);
    string grpstr = String.trim_all_whites(permit->get_data());
    object grp = get_module("groups")->lookup(grpstr);
    if ( !objectp(grp) )
      steam_error("Unknown group in permit %s", permit->get_xml());
    commands += spm_cmd(obj, "sanction", grp, accessBit);
  }
  return commands;
}

static array setup_attributes(object obj, object attributes)
{
  array commands = ({ });
  if ( !objectp(attributes) )
    return commands;
  foreach(attributes->get_nodes("attribute"), object attribute) {
    string key;
    mixed val;
    key = attribute->attributes->name;
    if ( !stringp(key) )
      steam_error("Failed to setup attributes in %s, missing key", 
                  attribute->get_xml());
    object datanode = attribute->get_first_child();
    if ( !objectp(datanode) ) {
      // try to get plain types
      int v;
      sscanf(attribute->get_data(), "%d", v);
      if ( (string)v == val )
        val = (int)v;
      else
        val = attribute->get_data();
    }
    else {
      val = xmlDom.unserialize(attribute->get_first_child());
    }
    commands += spm_cmd(obj, "attribute", key, val);
  }
  return commands;
}

static array setup_description(object obj, object desc)
{
  array commands = ({ });
  mapping descriptions = ([ ]);
  if ( !objectp(desc) )
    return commands;
  foreach(desc->get_nodes("desc"), object d) {
    string lang = d->attributes->lang;
    if ( !stringp(lang) )
      steam_error("No description for language node in %s", desc->get_xml());
    descriptions[lang] = d->get_data();
  }
  commands += spm_cmd(obj, "attribute", "OBJ_DESCS", descriptions);
  return commands;
}

static mapping setup_package(object dest, object setup, array files) 
{
  if ( !objectp(setup) )
    return ([ ]);
  // parse setup file
  mapping commands = ([ ]);

  foreach ( files, object f ) {
    if ( objectp(f) && f->get_object_class() & CLASS_DOCXSL ) {
      object xgl = f->find_xml();
      if ( objectp(xgl) )
        xgl->set_attribute(DOC_LAST_MODIFIED, time()); // update scripts!
      mixed err = catch(f->load_xml_structure());
      if ( err ) {
	spm_log(dest,"install.log", "Failed to load XML Structure for %O",f->get_identifier());
	FATAL("Failed to load XML for %O\n%O\n%O", f, err[0], err[1]);
      }
    }
  }
  
  mapping filemap = mkmapping(map(files, _FILEPATH->object_to_filename),files);
  LOG_SPM("filemap=%O\n", filemap);

  object rootNode = xmlDom.parse(setup->get_content());
  foreach(rootNode->get_nodes("object"), object node) {
    object obj = filemap[node->attributes->path];
    //_FILEPATH->path_to_object(node->attributes->path);
    if ( !objectp(obj) )
      obj = OBJ(node->attributes->path);
    
    LOG_SPM("Found OBJ Match=%O for %s\n", obj, node->attributes->path);
    if ( !objectp(obj) ) {
      spm_log(dest, "install.log", "Failed to find object for %s",
              node->attributes->path);
      continue;
    }
    commands[obj] = ({ });

    object access = node->get_node("access");
    commands[obj] += setup_access(obj, access);
    object attributes = node->get_node("attributes");
    commands[obj] += setup_attributes(obj, attributes);
    object publish = node->get_node("publish");
    object desc = node->get_node("description");
    commands[obj] += setup_description(obj, desc);

    if ( objectp(publish) )
      commands[obj] += spm_cmd(obj, "publish", publish->get_data());
    LOG_SPM("Commands are %O\n", commands[obj]);
    //spm_execute_commands(obj, commands[obj]); // for testing execute directly
  }
  return commands;
}

static array spm_cmd(object obj, string type, mixed ... args) 
{
  if ( !stringp(type) )
    steam_error("Wrong parameter 'type' for spm command !");
  return ({ ([ "object": obj, "type": type, "args": args, ]) });
}

static void spm_execute_commands(object obj, array commands)
{
  mixed err;

  foreach(commands, mapping cmd) {
    switch( cmd->type ) {
    case "attribute":
      // set acquire to zero first
      err = catch {
        cmd->object->set_acquire_attribute(cmd->args[0]);
        cmd->object->set_attribute(@cmd->args);
      };
      if ( err ) {
        FATAL("Failed to set attribute %O in %O to %O\n%O\n%O", 
              cmd->args[0], 
              cmd->object,
              @cmd->args,
              err[0],
              err[1]);
      }
      break;
    case "publish":
      err = catch(cmd->object->set_attribute(OBJ_URL, @cmd->args));
      if ( err ) 
        FATAL("Failed to set URL for %O to %O\n%O\n%O", 
              cmd->object, @cmd->args,
              err[0], err[1]);
      break;
    case "sanction":
      cmd->object->sanction_object(@cmd->args);
      break;
    case "acquire":
      cmd->object->set_acquire(@cmd->args);
      break;
    }
  }
}

string command_to_xml(mapping cmd)
{
  werror("object: %O\n", cmd->object);
  werror("type: %O\n", cmd->type);
  werror("args:; %O\n", compose(cmd->args));
  return sprintf("<command type='%s'><object><id>%d</id><path>%s</path></object><args>%s</args></command>\n", cmd->type, cmd->object->get_object_id(), _FILEPATH->object_to_filename(cmd->object),compose(cmd->args)); 
}

void run_install_spm(object spm, object dest, object result)
{
  oHandler = result;
  array files = get_module("tar")->unpack(spm);
  object cont = get_factory(CLASS_CONTAINER)->execute((["name":"temp",]));
  foreach(files, object f) f->move(cont);
  result->output("All Files unpacked.<br/>");
  result->output("Installing SPM.<br/>");
  
  mapping commands;
  mixed err = catch(commands = install_spm(cont, dest, false));
  if (err) {
    result->output("Error on Installation !<br/>");
    result->output(sprintf("%O<br/>", err[0]));
    result->asyncResult(0, sprintf("Backtrace: <br/>%O<br/>", err[1]));
    oHandler = 0;
    return;
  }
#if 0 // do not convert to xml  
  string xml = "<?xml version='1.0' encoding='utf-8'?>";
  xml += "<setup>\n";
  
  foreach (indices(commands), object obj) {
    foreach(commands[obj], mapping cmd)
      xml += command_to_xml(cmd);
  }
  xml += "</setup>\n";
  // transform
  object xsl = OBJ("/packages/spm_support/stylesheets/setup.xsl");
  int id = time();
  mSetups[id] = get_module("libxslt")->run(xml, xsl, ([ ]));
  mSetups[id+1] = commands;
  result->asyncResult(0, "<script type='text/javascript'>\nwindow.location.href='/SPM?_action=setup&id="+id+"';\n</script>");
#else
  result->asyncResult(0, "<script type='text/javascript'>\nwindow.location.href='/packages';\n</script>");
#endif
  oHandler = 0;
}


mixed execute(mapping vars)
{
    switch ( vars->_action ) {
    case "install":
        object package = find_object((int)vars->install);
        // timeout ?
	if ( !objectp(package) )
	    return error_page("Cannot install package: not found !");
        object result = SPMHtmlHandler();
	call(run_install_spm, 0, package, OBJ("/"), result);
        return result;
	break;
    case "setup":
        string html = mSetups[(int)vars->id];
	return html;
    case "upload":
	string name = basename(vars["paket.filename"]);
	if ( !stringp(name) || name == "" ) 
	  steam_user_error("No Name set for package !");
	object pdoc = get_factory(CLASS_DOCUMENT)->execute( (["name":name,]));
	pdoc->set_content(vars->paket);
	pdoc->move(OBJ("/packages"));
	break;
    case "uninstall":
	object cont = find_object((int)vars->id);
        uninstall_spm(cont);
	break;
    case "delete":
	object obj = find_object((int)vars->id);
	if ( objectp(obj) )
	    obj->move(this_user()->query_attribute(USER_TRASHBIN));
	break;
    case "show_install_log":
	object spm = find_object((int)vars->id);
	if ( objectp(spm) ) {
	    return result_page(
		replace(spm_read_log(spm, "install.log"), "\n", "<br />"), 
		"/packages");
	}
	break;
    }

    foreach(values(mLogs), object l)
      if ( objectp(l) )
        catch(l->close());

    return redirect("/packages");
}

/**
 * This function takes a container and reads all xml files in it (config files). The
 * files contents is joined into a single xml string.
 *  
 * @param object container - the container with xml configurations in it
 * @return xml of the joined configuration files.
 */
object spm_read_configuration(object container) 
{
    if ( !objectp(container) )
	return 0;
    
    array xmlInv = container->get_inventory_by_class(CLASS_DOCXML);
    array(object) xmlNodes = ({ });
    foreach ( xmlInv, object inv ) {
	object node = xmlDom.parse(inv->get_content());
	LOG_SPM("Dumping join node: %s\n", node->get_xml());
	xmlNodes += ({ node });
    }
    object config;
    if ( sizeof(xmlNodes) >= 1 ) {
	config = xmlNodes[0];
	for ( int i = 1; i < sizeof(xmlNodes); i++ ) {
	    config->join(xmlNodes[i]);
	}
    }
    return config;
}

int spm_version_value(string version)
{
    if ( !stringp(version) ) return 0;
    int minor, major, release;
    sscanf(version, "%d.%d.%d", release, major, minor);
    return release * 1000000 + major*1000 + minor;
}

int spm_match_versions(string version, string installedVersion)
{
    if ( !stringp(version) || !stringp(installedVersion) )
        return 0;

    string   val;
    int iVersion;

    iVersion = spm_version_value(installedVersion);

    if ( sscanf(version, ">=%s", val) ) {
	LOG_SPM("Iversion: %d, Version=%d\n", iVersion, spm_version_value(val));
	if ( spm_version_value(val) < iVersion )
	    return 1;
    }
    if ( sscanf(version, "==%s", val) ) {
	if ( spm_version_value(val) != iVersion )
	    return 1;
    }
    if ( sscanf(version, "<=%s", val) ) {
	if ( spm_version_value(val) > iVersion )
	    return 1;
    }
    else if ( sscanf(version, ">%s", val) ) {
	if ( spm_version_value(val) <= iVersion )
	    return 1;
    }
    else if ( sscanf(version, "<%s", val) ) {
	if ( spm_version_value(val) >= iVersion )
	    return 1;
    }
    return 0;
}

mapping spm_check_configuration(string config)
{
    mapping cfgMap = ([ ]);
    object node = xmlDom.parse(config);
    foreach(node->get_children(), object child) {
	if ( child->get_name() == "requires" ) {
	    if ( !spm_match_versions(child->attributes["server"],
				    _Server->get_version()) )
		steam_user_error("Server Version mismatch: need '"+ 
				 child->attributes->server + 
				 "' (Current Server Version is '"+
				 _Server->get_version()+"'");
	    foreach ( child->get_children(), object req ) {
		// check each require
		string modname = req->data;
		object module = get_module("package:"+modname);
		if ( !objectp(module) )
		    module = get_module(modname);
		
		if ( !objectp(module) ) 
		    steam_user_error(
			"Steam Packaging Error:\n"+
			"The required package '"+ modname + "' "+
			" is not installed !\n"+
			"Make sure that all required packages are installed " +
			"before installing this package.");
		string versionStr = "undefined";
                if ( functionp(module->get_version) )
                  versionStr = module->get_version();
		if ( !stringp(req->attributes->version) ) {
		    steam_user_error(
			"Steam Packaging Error:\n"+
			"No Version attribute for " + req->data);
		}
		if ( !spm_match_versions(req->attributes->version,versionStr) )
		{
		    steam_user_error(
			"Steam Packaging Error:\n"+
			"Requirement could not be fullfilled...\n"+
			"Package: '" + modname + " needs " + req->version +
			"(installed " + versionStr + ")");
		}
	    }
	}
	else {
	    cfgMap[child->get_name()] = child->get_data();
	}
    }
    if ( !stringp(cfgMap->name) )
	steam_user_error("Invalid configuration file - missing name !");
    return cfgMap;
}


string spm_get_configuration(object|string|int container) 
{
    if ( !objectp(container) )
	container = find_object(container);
    object node = spm_read_configuration(container);
    return node->get_xml();
}

object get_source_object() { return this(); } // script needs this!
string get_identifier() { return "SPM"; }
int get_object_class() { return ::get_object_class() | CLASS_SCRIPT; }


void test()
{
  // needs uploaded testspm.spm
  if ( objectp(OBJ("/spmtest")) )
    OBJ("/spmtest")->delete();
  
  object testspm = OBJ("/packages/testspm.spm");
  if ( !objectp(testspm) ) {
    Test.skipped( "spm", "testspm.spm not found in /packages" );
    return;
  }

  Test.test( "installing testspm.spm",
             install_spm(testspm, OBJ("/")) );

  Test.test( "upgrading testspm.spm",
             install_spm(testspm, OBJ("/")) );

  uninstall_spm(OBJ("/packages/testspm"));
  Test.test( "uninstalling testspm.spm",
             ( !objectp(OBJ("/spmtest")) ),
             "still remaining files left" );
}
