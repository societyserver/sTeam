inherit Service.Service;

void call_service(object user, mixed args, void|int id)
{
  
}

void install_spm(object spmModule, string pname) 
{
  object fp = connection->send_cmd(0, "get_module", "filepath:tree");
  object packages = fp->path_to_object("/packages");
  werror("Updating %O\n", pname);
  if ( objectp(packages) ) {
    // tarfs
    object tfs = Filesystem.Tar("spms/"+pname);
    if ( !objectp(tfs) ) {
      werror(": " + pname + " not a valid SPM !\n");
      return;
    }
    mixed xml = tfs->open("package.xml", "r");
    string packageXML = xml->read();
    xml->close();
    mapping config =spmModule->spm_check_configuration(packageXML);
    werror("CONFIG = %O\n", config);
    mapping pmod = connection->send_cmd(0, "get_module", config->name);
    if ( !objectp(pmod) )
      pmod = connection->send_cmd(0, "get_module", "package:"+config->name);
    if ( objectp(pmod) ) {
      if ( spmModule->spm_version_value(config->version) <= spmModule->spm_version_value(pmod->get_version()) ) {
	werror("Found installed module with version %O, skipping installation !\n", pmod->get_version());
	return;
      }
      else {
	werror("Found installed module - updating to %O (previous version %O)\n",
	       config->version, pmod->get_version());
      }
    }
    else {
      werror("Module " + config->name + " not found on server - installing\n");
    }
      
    Stdio.File file = Stdio.File("spms/"+pname, "r");
    object package = packages->get_object_byname(pname);
    if ( !objectp(package) ) {
      object docfactory = connection->get_variable("Document.factory");
      package = docfactory->execute( (["name": pname, ]));
      package->move(packages);
    }
    string spmContent = file->read();
    package->set_content(spmContent);
    string spmRealContent = package->get_content();
    werror("Content Length: %d and %d\n", strlen(spmContent), strlen(spmRealContent));
    for ( int i = 0; i < strlen(spmContent); i++ ) {
      if ( spmContent[i] != spmRealContent[i] ) {
	werror("SPM Differs in byte %d\n 100 bytes:\n%O\n------\n%O\n",
	       i, spmContent[i-50..i+50], spmRealContent[i-50..i+50]);
	error("SPM Differ!");
      }
    }
    spmModule->install_spm(package, fp->path_to_object("/"));
    return;
  }
  error("Failed to install - no /packages found on server");
}

static void check_spms()
{
  object _spm = connection->send_cmd( 0, "get_module", "SPM" );
  if ( !objectp(_spm) )
    werror("Failed to find SPM Module !\n");
  array directory = get_dir("spms");
  directory = sort(directory);
  foreach ( directory, string file ) {
    werror("file = %O\n", file);
    if ( sscanf(file, "%*s.spm") ) {
      mixed err = catch ( install_spm(_spm, file) );
      if ( err )
        werror( "Error while installing %s : %O\n%O", file, err[0], err[1] );
    }
  }
  call_out(check_spms, 30);
}

static void run()
{
  werror("cwd = " + getcwd() + "\n");
  check_spms();
}

static private void got_kill(int sig) {
	_exit(1);
}

int main(int argc, array argv)
{
  signal(signum("QUIT"), got_kill);
  init( "spm", argv );
  start();
  return -17;
}
