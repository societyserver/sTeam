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
object newfileobj;
string content;
int i=1;
int j=1;
int count=0;
int set=0;
string dir;
string debugfile;

void upload(object editor, string file, int last_mtime, object obj, object xslobj, function|void exit_callback, string|void olderrors)
{
  int exit_status = editor->status();
  object new_stat = file_stat(file);
  int new_mtime;
  string newcontent;
  string oldcontent = obj->get_content();  //currently changing 

  if((content!=oldcontent)&&(oldcontent!=("sTeam connection lost."||""))&&obj&&(i==1))
  {
    i=0;
    send_message("File changed on server.\n");
//Not needed -    Stdio.write_file(file, oldcontent||"", 0600);
    last_mtime = new_stat->mtime;
  }
  if (!new_stat)
    send_message(sprintf("%s is gone!", file));

  if (new_stat && new_stat->mtime > last_mtime)
  {
    new_mtime = new_stat->mtime;
    newcontent = Stdio.read_file(file);
    if (!stringp(newcontent))
      send_message(sprintf("failed to read %s", file));
  }

  if (stringp(newcontent) && newcontent != content && oldcontent!="sTeam connection lost.")
  {
    last_mtime=new_mtime;
    content = newcontent;  //update initial content to new after saving
    mixed result=obj->set_content(newcontent);
    string message=sprintf("File saved - upload: %O\n", result);
    olderrors = UNDEFINED;
    send_message(message);
    count=0;  //so that compile status can be rewritten for newfile
    if (xslobj)
    {
      result=xslobj->load_xml_structure();
      message=sprintf("%O: load xml struct: %O", xslobj, result);
      send_message(message);
    }
  }
  if(oldcontent=="sTeam connection lost.")
  {
    if(j==1){
      send_message("Disconnected\n");
      j--;
    }
      if(newfileobj)
      {
        send_message("Connected back\n");
        obj = newfileobj;
      }
  }

  if (exit_status != 2)
  {
    if(obj->get_class()=="DocLpc")  //if pike script .
    {
      array errors = obj->get_errors();
      string newerrors = sprintf("%O", errors);
      if (newerrors != olderrors)
      {
        olderrors = newerrors;
        send_message("-----------------------------------------\n");
        if(errors==({}))
          send_message("Compiled successfully\n");
        else
        {
          foreach(errors, string err)
            send_message(err);
          send_message("Compilation failed\n");
        }
        send_message("-----------------------------------------\n");
      }
    }
    call_out(upload, 1, editor, file, new_mtime, obj, xslobj, exit_callback, olderrors);
  }
  else if (exit_callback)
  {
    exit_callback(editor->wait());
//    exit(1);  
  }
}


void update(object obj)
{
  newfileobj = obj;
}

array edit(object obj)
{
#if constant(Crypto.Random)
  dir="/tmp/"+(MIME.encode_base64(Crypto.Random.random_string(10), 1)-("/"))+System.getpid();
#else
   dir="/tmp/"+(MIME.encode_base64(Crypto.randomness.pike_random()->read(10), 1)-("/"))+System.getpid();
#endif
  string filename=obj->get_object_id()+"-"+obj->get_identifier();

  debugfile = filename+"-disp";
  mkdir(dir, 0700);
  content=obj->get_content();  //made content global, this is content when vim starts and remains same. oldcontent keeps changing in upload function.
  //werror("%O\n", content);
  Stdio.write_file(dir+"/"+filename, content||"", 0600);
  
  Stdio.write_file(dir+"/"+debugfile, "This is your log window\n", 0600);
  array command;
  //array command=({ "screen", "-X", "screen", "vi", dir+"/"+filename });
  //array command=({ "vim", "--servername", "VIM", "--remote-wait", dir+"/"+filename });
    string enveditor = getenv("EDITOR");
  string name = dir+"/"+debugfile;
  if((enveditor=="VIM")||(enveditor=="vim"))    //full path to .vim files to be mentioned
    command=({ "vim","-S", "/usr/local/lib/steam/tools/watchforchanges.vim", "-S", "/usr/local/lib/steam/tools/golden_ratio.vim", dir+"/"+filename, "-c","set splitbelow", "-c"  ,sprintf("split|view %s",name), "-c", "wincmd w"});
  else if(enveditor=="emacs")
    command=({ "emacs", "--eval","(add-hook 'emacs-startup-hook 'toggle-window-spt)", "--eval", "(global-auto-revert-mode t)", dir+"/"+filename, dir+"/"+debugfile, "--eval", "(setq buffer-read-only t)", "--eval", sprintf("(setq frame-title-format \"%s\")",obj->get_identifier()) , "--eval", "(windmove-up)", "--eval", "(enlarge-window 5)"});
  else
    command=({ "vi","-S", "/usr/local/lib/steam/tools/watchforchanges.vim", "-S", "/usr/local/lib/steam/tools/golden_ratio.vim", dir+"/"+filename, "-c","set splitbelow", "-c"  ,sprintf("split|view %s",name), "-c", "wincmd w"});

  object editor=Process.create_process(command,
                                     ([ "cwd":getenv("HOME"), "env":getenv(), "stdin":Stdio.stdin, "stdout":Stdio.stdout, "stderr":Stdio.stderr ]));
  return ({ editor, dir+"/"+filename });
} 

int send_message(string message)
{
/*
  if (getenv("STY"))
      Process.create_process(({ "screen", "-X", "wall", message }));
  else if (getenv("TMUX"))
      Process.create_process(({ "tmux", "display-message", message }));
  else
      werror("%s\n", message);
*/
  Stdio.append_file(dir+"/"+debugfile, message||"", 0600); //result buffer
}

int applaunch(object obj, function exit_callback)
{
  object xslobj;
  if(obj->get_identifier()[sizeof(obj->get_identifier())-8..]==".xsl.xml")
  {
    string xslname=
      obj->get_identifier()[..sizeof(obj->get_identifier())-9]+ ".xsl";
    xslobj=obj->get_environment()->get_object_byname(xslname);
  }

  object editor;
  string file;
  [editor, file]=edit(obj);
  mixed status;
  //while(!(status=editor->status()))

  send_message(sprintf("(opened %O %s)\n", obj, file));
  call_out(upload, 1, editor, file, file_stat(file)->mtime, obj, xslobj, exit_callback);

//  signal(signum("SIGINT"), prompt);
  return -1;
}
