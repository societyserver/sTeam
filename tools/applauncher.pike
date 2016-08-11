/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2003-2004  Martin Baehr
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
 * $Id: applauncher.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: applauncher.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//before using this file, patch the paths for watchforchanges.vim and golden_ratio.vim
array(object) newfileobjarr;
array(string) contentarr;
int i=1;
int k=1;
int count=0;
int set=0;
string dir;
array(string) debugfilearr;
array(string) olderrorsarr;
int exitcall=0;

void upload(object editor, array(string) filearr ,array(int) last_mtimearr, array(object) objarr, array(object) xslobjarr, function|void exit_callback)
{
  int exit_status = editor->status();
  int size = sizeof(filearr);
  array(object) new_statarr = allocate(size);
  array(int) new_mtimearr = allocate(size);
  array(string) new_errorarr = allocate(size);
  for(int j=0;j<size;j++){
    new_statarr[j] = file_stat(filearr[j]);
    string newcontentx;
    string oldcontentx = objarr[j]->get_content();
    if((contentarr[j]!=oldcontentx)&&(oldcontentx!=("sTeam connection lost."||""))&&objarr[j]&&(i==1))
    {
    i=0;
    send_message("File changed on server.\n",debugfilearr[j]);
    last_mtimearr[j] = new_statarr[j]->mtime;
    }

    if (!new_statarr[j])
      send_message(sprintf("%s is gone!", filearr[j]),debugfilearr[j]);

    if (new_statarr[j] && new_statarr[j]->mtime > last_mtimearr[j])
    {
    new_mtimearr[j] = new_statarr[j]->mtime;
    newcontentx = Stdio.read_file(filearr[j]);
    if (!stringp(newcontentx))
      send_message(sprintf("failed to read %s", filearr[j]),debugfilearr[j]);
    }


    if (stringp(newcontentx) && newcontentx != contentarr[j] && oldcontentx!="sTeam connection lost.")
    {
    last_mtimearr[j]=new_mtimearr[j];
    contentarr[j] = newcontentx;  //update initial content to new after saving
    mixed result=objarr[j]->set_content(newcontentx);
    string message=sprintf("File saved - upload: %O\n", result);
    olderrorsarr[j] = UNDEFINED;
    send_message(message,debugfilearr[j]);
    count=0;  //so that compile status can be rewritten for newfile
    if (xslobjarr[j])
    {
      result=xslobjarr[j]->load_xml_structure();
      message=sprintf("%O: load xml struct: %O", xslobjarr[j], result);
      send_message(message,debugfilearr[j]);
    }
    }

    if(oldcontentx=="sTeam connection lost.")
    {
    if(k==1){
      send_message("Disconnected\n",debugfilearr[j]);
      k--;
    }
      if(newfileobjarr[j])
      {
        send_message("Connected back\n",debugfilearr[j]);
        objarr[j] = newfileobjarr[j];
      }
    }

    if (exit_status != 2)
    {
    if(objarr[j]->get_class()=="DocLpc")  //if pike script .
    {
      array errors = objarr[j]->get_errors();
 //     string newerrors = sprintf("%O", errors);
      new_errorarr[j] = sprintf("%O", errors);
      if (new_errorarr[j] != olderrorsarr[j])
      {
        olderrorsarr[j] = new_errorarr[j];
        send_message("-----------------------------------------\n",debugfilearr[j]);
        if(errors==({}))
          send_message("Compiled successfully\n",debugfilearr[j]);
        else
        {
          foreach(errors, string err)
            send_message(err,debugfilearr[j]);
          send_message("Compilation failed\n",debugfilearr[j]);
        }
        send_message("-----------------------------------------\n",debugfilearr[j]);
      }
    }
    }
  else if (exit_callback)
  {
    exit_callback(editor->wait());
    if(exitcall==1)
	exit(1);  
  }
  
  }
  if(exit_status !=2)
    call_out(upload, 1, editor, filearr, new_mtimearr, objarr, xslobjarr, exit_callback);
}


void update(array(object) obj)
{
  newfileobjarr = allocate(sizeof(obj));
  for(int j = 0; j < sizeof(obj); j++)
    newfileobjarr[j] = obj[j];
}

array edit(array(object) objarr)
{
#if constant(Crypto.Random)
  dir="/tmp/"+(MIME.encode_base64(Crypto.Random.random_string(10), 1)-("/"))+System.getpid();
#else
   dir="/tmp/"+(MIME.encode_base64(Crypto.randomness.pike_random()->read(10), 1)-("/"))+System.getpid();
#endif
  int size = sizeof(objarr); //get the number of files
  contentarr=allocate(size); //made content global, this is content when vim starts and remains same. oldcontent keeps changing in upload function.
  debugfilearr=allocate(size);
  array(string) filenamearr = allocate(size);


  mkdir(dir, 0700);

  //get the filename and debugfile name for all the files
  //also get content for all the files
  //initialize the files

  for(int j = 0; j < size; j++){
    filenamearr[j] = objarr[j]->get_object_id()+"-"+objarr[j]->get_identifier();
    debugfilearr[j] = filenamearr[j]+"-disp";
    contentarr[j] = objarr[j]->get_content();
    filenamearr[j]=dir+"/"+filenamearr[j];
    Stdio.write_file(filenamearr[j], contentarr[j]||"", 0600);
    debugfilearr[j]=dir+"/"+debugfilearr[j];
    Stdio.write_file(debugfilearr[j], "This is your log window\n", 0600);
  }

  string comm;//command in string form
  array command;
  
  //array command=({ "screen", "-X", "screen", "vi", dir+"/"+filename });
  //array command=({ "vim", "--servername", "VIM", "--remote-wait", dir+"/"+filename });
  
  string enveditor = getenv("EDITOR");
  
  
  if((enveditor=="VIM")||(enveditor=="vim")){    //full path to .vim files to be mentioned
    comm="sudo*vim*-S*/usr/local/lib/steam/tools/steam-shell.vim*-S*/usr/local/lib/steam/tools/watchforchanges.vim*-S*/usr/local/lib/steam/tools/golden_ratio.vim*-c*edit "+debugfilearr[0]+"|sp "+filenamearr[0];
    if(size>1)
      comm = add_file_name(comm,filenamearr[1..],debugfilearr[1..]);
    }
  else if(enveditor=="emacs"){
    comm="emacs*--eval*(add-hook 'emacs-startup-hook 'toggle-window-spt)*--eval*(global-auto-revert-mode t)";
    for(int j = 0;j<size;j++){
      comm=comm+"*"+filenamearr[j]+"*"+debugfilearr[j];
    }
    comm=comm+"*--eval*(setq buffer-read-only t)*--eval*"+sprintf("(setq frame-title-format \"%s\")",objarr[0]->get_identifier()) +"*--eval*(windmove-up)*--eval*(enlarge-window 5)";
    }
  else{
     comm="sudo*vi*-S*/usr/local/lib/steam/tools/steam-shell.vim*-S*/usr/local/lib/steam/tools/watchforchanges.vim*-S*/usr/local/lib/steam/tools/golden_ratio.vim*-c*edit "+debugfilearr[0]+"|sp "+filenamearr[0];

    if(size>1)
      comm = add_file_name(comm,filenamearr[1..],debugfilearr[1..]);
    }
    
    command=comm/"*"; // convert the string to array.

  object editor=Process.create_process(command,
                                     ([ "cwd":getenv("HOME"), "env":getenv(), "stdin":Stdio.stdin, "stdout":Stdio.stdout, "stderr":Stdio.stderr ]));
  return ({ editor,filenamearr});
} 

string add_file_name(string command,array(string) arr,array(string) debug){
  int size = sizeof(arr);
  for(int j=0;j<size;j++){
    command = command+"|tabe "+debug[j]+"|sp "+arr[j];
  }
  return command;
}

int send_message(string message,string debugfile)
{
  Stdio.append_file(debugfile, message||"", 0600); //result buffer
}

int applaunch(array(object) objarr,function exit_callback)
{
  int size = sizeof(objarr);
  array(object) xslobjarr = allocate(size);
  for(int j = 0; j < size; j++){
    if(objarr[j]->get_identifier()[sizeof(objarr[j]->get_identifier())-8..]==".xsl.xml")
    {
    string xslnamex=
      objarr[j]->get_identifier()[..sizeof(objarr[j]->get_identifier())-9]+ ".xsl";
    xslobjarr[j]=objarr[j]->get_environment()->get_object_byname(xslnamex);
    }
  }

  object editor;
  array(string) filearr;
  [editor,filearr]=edit(objarr);
 
 // mixed status;
  //while(!(status=editor->status()))
 
  array(int) filestatarr = allocate(size);
  for(int j = 0; j < size; j++){
    send_message(sprintf("(opened %O %s)\n", objarr[j], filearr[j]),debugfilearr[j]);
    filestatarr[j] =  file_stat(filearr[j])->mtime;
  }

  olderrorsarr = allocate(size);
  call_out(upload, 1, editor, filearr, filestatarr, objarr, xslobjarr, exit_callback);
  if(exitcall==0) //exitcall = 0 means it is called by steam-shell otherwise by edit.pike
    editor->wait();

//  signal(signum("SIGINT"), prompt);
  
  return -1;
}


int vim_upload(array(string) filearr, array(object) objarr, array(object) xslobjarr, function|void exit_callback)
{
  int size = sizeof(filearr);
  string newcontentx;
  array(object) new_statarr = allocate(size);
  array(string) new_errorarr = allocate(size);
  debugfilearr=allocate(size);
  for(int j=0;j<size;j++){
    debugfilearr[j]=filearr[j]+"-disp";
    new_statarr[j] = file_stat(filearr[j]);
    
    string oldcontentx = objarr[j]->get_content();
    
    if (!new_statarr[j])
      send_message(sprintf("%s is gone!", filearr[j]),debugfilearr[j]);

    if (new_statarr[j])
    {
    newcontentx = Stdio.read_file(filearr[j]);
    if (!stringp(newcontentx))
      send_message(sprintf("failed to read %s", filearr[j]),debugfilearr[j]);
    }


    if (stringp(newcontentx) && oldcontentx!="sTeam connection lost.")
    {
      mixed result=objarr[j]->set_content(newcontentx);
      string message=sprintf("File saved - upload: %O\n", result);
      send_message(message,debugfilearr[j]);
      count=0;  //so that compile status can be rewritten for newfile
      if (xslobjarr[j])
      {
        result=xslobjarr[j]->load_xml_structure();
        message=sprintf("%O: load xml struct: %O", xslobjarr[j], result);
        send_message(message,debugfilearr[j]);
      }
    }

    if(oldcontentx=="sTeam connection lost.")
    {
    if(k==1){
      send_message("Disconnected\n",debugfilearr[j]);
      k--;
    }
      if(newfileobjarr[j])
      {
        send_message("Connected back\n",debugfilearr[j]);
        objarr[j] = newfileobjarr[j];
      }
    }

    
    if(objarr[j]->get_class()=="DocLpc")  //if pike script .
    {
      array errors = objarr[j]->get_errors();
      new_errorarr[j] = sprintf("%O", errors);
      send_message("-----------------------------------------\n",debugfilearr[j]);
      if(errors==({}))
        send_message("Compiled successfully\n",debugfilearr[j]);
      else
      {
        foreach(errors, string err)
          send_message(err,debugfilearr[j]);
        send_message("Compilation failed\n",debugfilearr[j]);
      }
      send_message("-----------------------------------------\n",debugfilearr[j]);
    }
  }
}
