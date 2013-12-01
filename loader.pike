/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: loader.pike,v 1.7 2009/08/04 15:33:19 nicke Exp $
 */

constant cvs_version="$Id: loader.pike,v 1.7 2009/08/04 15:33:19 nicke Exp $";


#include <configure.h>

mapping env = ([
    "LD_LIBRARY_PATH":getcwd()+"/server/libraries:/usr/local/lib",
    ]);


int quiet;
string     pidfile;
Stdio.File outfile;
Stdio.File errfile;
int   run_once = 0;
int          t = 0;
string     gdb = 0;
string      logdir;

string server_ip;

mapping    mServices;
mapping mServiceLogs;
mapping mServicePIDs;
int serverPID;
int loaderPID;

static int restart = 0;

static int keep_services_running = 1;


void MSG ( string msg, mixed ... args ) {
  if ( quiet ) return;
  write( msg, @args );
}

void ERR ( string msg, mixed ... args ) {
  if ( quiet ) return;
  werror( msg, @args );
}



array get_pids_from_pidfile () {
  if ( !stringp(pidfile) ) return 0;
  mixed err = catch {
    string pid_content = Stdio.read_file( pidfile );
    if ( !stringp(pid_content) || sizeof(pid_content) < 1 ) return 0;
    array pids = replace( pid_content, "\n", " " ) / " ";
    for ( int i=0; i<sizeof(pids); i++ ) pids[i] = (int)(pids[i]);
    // make sure the loader PID is always the first one in the array:
    if ( search( pids, serverPID ) >= 0 ) {
      pids -= ({ serverPID });
      pids = ({ serverPID }) + pids;
    }
    if ( search( pids, loaderPID ) >= 0 ) {
      pids -= ({ loaderPID });
      pids = ({ loaderPID }) + pids;
    }
    pids -= ({ 0 });
    return pids;
  };
  if ( err )
    ERR( "Error while trying to read pidfile %s :\n%O\n", pidfile, err );
  return 0;
}

int write_pids_to_pidfile ( array pids ) {
  if ( !arrayp(pids) ) return 0;
  array new_pids = pids - ({ loaderPID, serverPID, 0 });
  if ( serverPID != 0 ) new_pids = ({ serverPID }) + new_pids;
  for ( int i=0; i<sizeof(new_pids); i++ ) new_pids[i] = (string)(new_pids[i]);
  mixed err = catch {
    Stdio.write_file( pidfile, (string)loaderPID + "\n" + (new_pids * " ") );
    return 1;
  };
  if ( err )
    ERR( "Error while trying to write pidfile %s :\n%O\n", pidfile, err );
  return 0;
}

int add_pid_to_pidfile ( int pid ) {
  if ( pid == 0 ) return 0;
  array pids = get_pids_from_pidfile();
  if ( !arrayp(pids) ) return 0;
  if ( search( pids, pid ) < 0 ) pids += ({ pid });
  return write_pids_to_pidfile( pids );
}


int remove_pid_from_pidfile ( int pid ) {
  if ( pid == 0 || pid == loaderPID ) return 0;
  array pids = get_pids_from_pidfile();
  if ( !arrayp(pids) ) return 0;
  return write_pids_to_pidfile( pids - ({ pid }) );
}


object start_service(string service, string ticket) 
{
  array loader_args = ({ });
  mapping config = Config.read_config_file( CONFIG_DIR + "/services/" + service + ".cfg" );
  if ( mappingp(config) && stringp(config["loader_args"]) )
    loader_args += (config["loader_args"] / " ");

  array(string) runArr = ({ "bin/"+BRAND_NAME });
  runArr += loader_args;
  Stdio.File serviceLog = Stdio.File(logdir + "/"+service + ".log", "wct");
  Stdio.File ipc = Stdio.File();

  if ( search(service, ".jar") > 0 ) {
    string java = "java";
    string java_home = getenv()["JAVA_HOME"];
    if ( stringp(java_home) )
      java = java_home + "/bin/java";
    runArr = ({ java, "-Djava.awt.headless=true" });
    runArr += loader_args;
    runArr += ({ "-jar", "services/"+service });
  }
  else
    runArr += ({ "services/"+service });

  //runArr += ({ "--user=service", "--password="+ticket });
  mapping envMap = getenv();
  if ( !mappingp(envMap) ) envMap = ([ ]);
  envMap["STEAM_SERVICE_USER"] = "service";
  envMap["STEAM_SERVICE_PASSWORD"] = ticket;

  if ( stringp(server_ip) ) runArr += ({ "--host="+server_ip });

  serviceLog->write( "[%s] Starting service \"%s\" ...\n", timelib.log_time(), service );
  if ( sizeof( loader_args ) > 0 )
    serviceLog->write( "[%s] Loader arguments: %O\n", timelib.log_time(), loader_args );
  mServiceLogs[service] = serviceLog;
  return Process.create_process( runArr,
				 ([ "env": envMap,
				    "cwd": getcwd(),
				    "stdout": serviceLog,
				    "stderr": serviceLog,
				 ]));
}

void start_services()
{
  mServices = ([ ]);
  mServiceLogs = ([ ]);
  mServicePIDs = ([ ]);
  
  array dir = get_dir("services");
  MSG("Starting services: ");
  if ( arrayp(dir) ) {
    foreach(dir, string service) {
      if ( !Stdio.is_file("services/"+service) )
	continue;
      if ( search(service, "~") >= 0 || search(service, "CVS") >= 0 )
	continue;
      MSG(" " + service + ", ");
      mServices[service] = 1;
    }
  }
  MSG("\n");
  keep_services_running = 1;
  thread_create(check_services);
}

void stop_service ( string service )
{
    int pid = mServicePIDs[service];

    // quit process:
    if ( objectp(mServices[service]) && mServices[service]->status() != 0 )
	mServices[service]->kill(signum("SIGQUIT"));
    else if ( pid != 0 )
	kill( pid, signum("SIGQUIT") );

    // if service doesn't quit, kill it:
    if ( objectp(mServices[service]) && mServices[service]->status() != 0 )
	mServices[service]->kill(signum("SIGKILL"));
    else if ( pid != 0 )
	kill( pid, signum("SIGKILL") );

    if ( pid != 0 ) {
      if ( remove_pid_from_pidfile( pid ) )
        mServicePIDs[service] = 0;
      else
	ERR( "Could not remove service \"%s\" PID %d from pidfile\n",
                service, pid );
    }
}

void stop_services ()
{
    keep_services_running = 0;
    if ( !mappingp(mServices) ) return;
    foreach(indices(mServices), string service)
	stop_service( service );
}

void check_services() 
{
  string ticket;

  while ( !stringp(ticket) ) {
    sleep(20);
    catch(ticket = Stdio.read_file("service.pass"));
  }
  
  catch(rm("service.pass"));
  
  while ( keep_services_running ) {
    foreach(indices(mServices), string service) {
      if ( !objectp(mServices[service]) || mServices[service]->status() > 0 ) {
	stop_service( service );
	if ( ! keep_services_running ) break;
        // start service:
	mixed err = catch(mServices[service] = start_service(service, ticket));
	if ( err ) {
	    mServiceLogs[service]->write("Failed to start service %s\n%O\n",
					 service, err);
	}
	else {
	  if ( !mServices[service] )
	      mServiceLogs[service]->write(
		  "Fatal Error - failed to start service %s.\n", service);
	  else {
              mServiceLogs[service]->write("[%s] PID: %d\n", timelib.log_time(),
					   mServices[service]->pid());
	      mServicePIDs[service] = mServices[service]->pid();
              if ( !add_pid_to_pidfile( mServices[service]->pid() ) )
                ERR( "Could not add service \"%s\" PID %d to pidfile.\n",
                        service, mServices[service]->pid() );
	  }
	}
      }
    }
    sleep(60);
  }
}


//! run the server
void run(array(string) params)
{
    int ret = 0;

    // ServerGate and ServerGateFactory are deprecated, but there might still
    // be stale files from older sTeam installations:
    rm( "server/classes/ServerGate.pike" );
    rm( "server/factories/ServerGateFactory.pike" );

    Stdio.File exitF;
    array(string) runArr = ({ "bin/"+BRAND_NAME, "server/server.pike" }) + params[1..];
    foreach (params, string p) {
      if ( p == "--auto-restart" )
	restart = 1;
    }
    if ( stringp(gdb) ) {
        runArr = ({ "gdb", "steam", "-x", "gdb.run" });
        Stdio.File gdb_file = Stdio.File("gdb.run", "wct");
        gdb_file->write(gdb);
        gdb_file->write((params[1..]*" ")+"\n");
        gdb_file->close();
    }
    string cwd = getcwd();
    mapping cenv = getenv();
    
    rm(logdir+"/exit");
    while ( ret != 1 && ret != 10 && (ret>=0 || restart) ) {
	MSG("\nCWD: " + getcwd() + " - Starting sTeam Server\n");
	MSG("------------------------------------------------------\n");
	MSG("Logfile: "+ sprintf("%O", outfile)+"\n");
	MSG("LogDir:  "+logdir+"\n");
	MSG("Params:  "+sprintf("%O", params[1..])+"\n");
	start_services();
        object server_process = Process.create_process( runArr,
	    ([ "env": cenv + env,
	       "cwd": cwd,
               "stdout": outfile,
               "stderr": errfile,
	     ]) );
        serverPID = server_process->pid();
        if ( serverPID != 0 && !add_pid_to_pidfile( serverPID ) )
          ERR( "Could not add server PID %d to pidfile %s !\n", serverPID,
                  pidfile );
        ret = server_process->wait();
        remove_pid_from_pidfile( serverPID );
        serverPID = 0;
	MSG("Returned: "+  ret+"\n");
	stop_services();
        mixed err = catch {
          if ( ContentFilesystem.unmount() )
            outfile->write( sprintf( "[%s] Content filesystem unmounted\n",
                               Calendar.Second(time())->format_time() ) );
        };
        if ( err ) ERR( err[0] );

        if ( ret > 0 ) {
            exitF = Stdio.File(logdir+"/exit", "wct");
            exitF->write("Server exited with error...\n");
            exitF->close();
        }
	if ( stringp(gdb) )
	    ret = 1;
	outfile->close();
	errfile->close();
	rotate_log("server.log");
	rotate_log("errors.log");
	rotate_log("http.log");
	rotate_log("events.log");
        rotate_log("smtp.log");
        rotate_log("security.log");
        rotate_log("slow_requests.log");

	outfile = Stdio.File(logdir+"/server.log", "wct");
	errfile = Stdio.File(logdir+"/errors.log", "wct");
    }
    ERR("sTeam Server Exited !\n");
    rm(pidfile);
    exit(ret);
}

#define LOGROTATE_DEPTH 5

void rotate_log(string logfile) 
{

  for ( int i = LOGROTATE_DEPTH; i > 0; i-- ) {
    string fromlog, tolog;
    if ( i > 1 )
      fromlog = logdir + "/" + logfile + "." + (i-1);
    else
      fromlog = logdir + "/" + logfile;
    tolog = logdir + "/" + logfile + "." + i;
    mv(fromlog, tolog);
// TODO: fix warnings for zip compression; add flag in steam.cfg
//   Process.create_process( ({ "gzip", tolog }), 
//			    ([ "env": getenv(),
//			       "cwd": getcwd(),
//			       "stdout": Stdio.stdout,
//			       "stderr": Stdio.stderr,
//			    ]) );
  }
}
    
void got_kill(int sig)
{
    restart = 0;
    ERR("Server killed !\n");
    stop_services();
    array pids = get_pids_from_pidfile();
    if ( !arrayp(pids) ) {
      ERR( "Could not open pidfile, only killing server (pid %d)\n",
              serverPID );
      kill( serverPID, signum("SIGQUIT") );
      return;
    }
    foreach ( pids, int pid ) {
        if ( pid != getpid() ) {
	    ERR( "Killing: %d\n", pid );
	    kill( pid, signum("SIGQUIT") );
	}
    }
}

void got_hangup(int sig)
{
    if ( run_once )
        got_kill(sig);
}

int 
main(int argc, array(string) argv)
{
    loaderPID = getpid();
    
    signal(signum("QUIT"), got_kill);
    signal(signum("TERM"), got_kill);
    signal(signum("SIGHUP"), got_hangup);
    signal(signum("SIGINT"), got_hangup);

    string sandbox = STEAM_DIR + "/tmp";
    mapping server_config = Config.read_config_file( CONFIG_DIR + "/steam.cfg" );
    if ( mappingp(server_config) ) {
      if ( stringp(server_config["ip"]) && sizeof(server_config["ip"])>1 )
	server_ip = server_config["ip"];
      else
	server_ip = 0;
      if ( stringp(server_config["sandbox"]) && server_config["sandbox"]!="" )
        sandbox = server_config["sandbox"];
    }
    server_config = 0;
    
    pidfile = getcwd() + "/steam.pid";
    logdir = LOG_DIR;

    string logfile_mode = "wct";
    int stopping = 0;
    int restarting = 0;
    foreach ( argv, string arg ) {
      if ( arg == "--stop" ) {
        stopping = 1;
        logfile_mode = "w";
        break;
      }
      else if ( arg == "--restart" ) {
        restarting = 1;
        logfile_mode = "w";
        break;
      }
    }

    foreach(argv, string p) {
	string a,b;
	if ( sscanf(p, "--%s=%s", a, b) == 2 ) {
	    switch( a ) {
	    case "pid":
	    case "pidfile":
		pidfile = b;
		break;
            case "stdout":
                outfile = Stdio.File(b, logfile_mode); 
		logdir="logs";
                break;
	    case "stderr":
                errfile = Stdio.File(b, logfile_mode);
		break;
	    case "logdir":
		outfile = Stdio.File(b + "/server.log", logfile_mode);
                errfile = Stdio.File(b + "/errors.log", logfile_mode);
		logdir = b;
		break;
	    }
	}
        if ( p == "--quiet" )
            quiet = 1;
        if ( p == "--once" && !stopping ) {
            outfile = Stdio.stdout;
	    errfile = Stdio.stderr;
            run_once = 1;
        }
        else if ( p == "--gdb" && !stopping ) {
            gdb = "run -I server/include -M server/libraries -P server "+
                  "server/server.pike ";
	    outfile = Stdio.stdout;
	}	
    }

    if ( !objectp(errfile) )
      errfile = Stdio.File(logdir+"/errors.log", logfile_mode);

    if ( !objectp(outfile) ) {
        outfile = Stdio.File(logdir+"/server.log", logfile_mode);
	logdir = LOG_DIR;
    }

    if ( stopping ) {
      kill( loaderPID, signum("TERM") );
      return 0;
    }
    else if ( restarting ) {
      if ( sandbox[-1] != '/' ) sandbox += "/";
      Stdio.write_file( sandbox + "server.restart", ctime(time()) );
      kill( loaderPID, signum("TERM") );
      return 0;
    }

    if ( !write_pids_to_pidfile( ({ loaderPID }) ) )
      ERR( "Could not add loader PID %d to pidfile %s !\n", loaderPID,
              pidfile );
    thread_create(run, argv);
    return -17;
}
