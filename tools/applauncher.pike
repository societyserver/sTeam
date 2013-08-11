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

void upload(object editor, string file, int last_mtime, object obj, object xslobj, function|void exit_callback)
{
  int exit_status = editor->status();
  object new_stat = file_stat(file);
  int new_mtime;
  string newcontent;

  if (!new_stat)
    send_message(sprintf("%s is gone!", file));

  if (new_stat && new_stat->mtime > last_mtime)
  {
    new_mtime = new_stat->mtime;
    newcontent = Stdio.read_file(file);
    if (!stringp(newcontent))
      send_message(sprintf("failed to read %s", file));
  }

  if (stringp(newcontent) && newcontent != obj->get_content())
  {
    last_mtime=new_mtime;
    mixed result=obj->set_content(newcontent);
    string message=sprintf("%O: upload: %O", obj, result);
    send_message(message);
    if (xslobj)
    {
      result=xslobj->load_xml_structure();
      message=sprintf("%O: load xml struct: %O", xslobj, result);
      send_message(message);
    }
  }

  if (exit_status != 2)
    call_out(upload, 1, editor, file, new_mtime, obj, xslobj, exit_callback);
  else if (exit_callback)
    exit_callback(editor->wait());
}


array edit(object obj)
{
#if constant(Crypto.Random)
  string dir="/tmp/"+(MIME.encode_base64(Crypto.Random.random_string(10), 1)-("/"))+System.getpid();
#else
  string dir="/tmp/"+(MIME.encode_base64(Crypto.randomness.pike_random()->read(10), 1)-("/"))+System.getpid();
#endif
  string filename=obj->get_object_id()+"-"+obj->get_identifier();

  mkdir(dir, 0700);
  string content=obj->get_content();
  //werror("%O\n", content);
  Stdio.write_file(dir+"/"+filename, content||"", 0600);
  
  //array command=({ "screen", "-X", "screen", "vi", dir+"/"+filename });
  //array command=({ "vim", "--servername", "VIM", "--remote-wait", dir+"/"+filename });
  array command=({ getenv("EDITOR")||"vim", dir+"/"+filename });
  object editor=Process.create_process(command,
                                     ([ "cwd":getenv("HOME"), "env":getenv(), "stdin":Stdio.stdin, "stdout":Stdio.stdout, "stderr":Stdio.stderr ]));
  return ({ editor, dir+"/"+filename });
} 

int send_message(string message)
{
  if (getenv("STY"))
      Process.create_process(({ "screen", "-X", "wall", message }));
  else if (getenv("TMUX"))
      Process.create_process(({ "tmux", "display-message", message }));
  else
      werror("%s\n", message);
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

  call_out(upload, 1, editor, file, file_stat(file)->mtime, obj, xslobj, exit_callback);

//  signal(signum("SIGINT"), prompt);
  return -1;
}
