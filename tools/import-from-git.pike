#!/usr/local/lib/steam/bin/steam

#include "/usr/local/lib/steam/server/include/classes.h"
inherit .client;
inherit "/home/trilok/Desktop/my_gsoc_work/new/sTeam/tools/applauncher.pike";
#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

constant cvs_version="$Id: import-from-git.pike.in,v 1.1 2015/06/08 14:19:52 martin Exp $";

object _Server;
object file;
int main(int argc, array(string) argv)
{
    options=init(argv);
    array opt = Getopt.find_all_options(argv,aggregate(
    ({"update",Getopt.NO_ARG,({"-U","--update"})}),
    ({"restart",Getopt.NO_ARG,({"-R","--restart"})}),
    ({"append",Getopt.NO_ARG,({"-A","--append"})})));
    options += mkmapping(opt[*][0], opt[*][1]);
    options->src = argv[-2];    //~/tmp/hello
    options->dest = argv[-1];   //home_doc 
    _Server=conn->SteamObj(0);
    import_from_git(options->src, options->dest);
    return 0;
}

void import_from_git(string from, string to)
{
    write("inside import-from-git function\n");
    int i;
    if(check_steam_path(to)&&check_from_path(from))
    {
       write("steam path and from path are correct\n");
       int num_versions = get_num_versions(from);
       write("inside main : num_versions : "+(string)num_versions+"\n");
       for(i=(num_versions); i>=1; i--)
       {
        string content = git_version_content(from,(string)i);
        OBJ(to)->set_content(content);
       }
    }
}

int check_from_path(string path)
{
  if(path[-1]==47)    //remove last "/"
      path=path[ .. (strlen(path)-2)];

  string dir,filename;

  if(Stdio.exist(path))
  {
    write("from path exists\n");
    dir = dirname(path);
    filename = basename(path);
    Stdio.File output = Stdio.File();
    Process.create_process(({ "git", "rev-parse", "--is-inside-work-tree"}), ([ "env":getenv(), "cwd":dir , "stdout":output->pipe() ]))->wait();
    string result = output->read();
    if(result)
    {
      write("output is : "+result+"\n"+"returning 1\n");
      return 1;
    }
    else
    {
      write("output is :"+result+"\n"+"returning 0\n");
      return 0;
    }
  }
  return 0;
}


int check_steam_path(string path)
{
  if(path[-1]==47)    //remove last "/"
      path=path[ .. (strlen(path)-2)];
  int j=0;
  int i=0;
  string cur_path;
  array(string) test_parts;
  object cont;
  int num_objects_create=0;
  int res=0;
  array(string) parts = path/"/";
  parts = parts-({""});  //removing all blanks out
  if(parts[0]=="home" && strlen(parts)==2)    //home/coder not possible
      return 0;

  cur_path = path;

  for(j=(strlen(parts)-1); j>=0; j--)
  {
    write("Checking path : "+cur_path+"\n");
    cont=_Server->get_module("filepath:tree")->path_to_object(cur_path,true);
    if(cont)
    {
        write("Got correct path as : "+cur_path+"\n");
        test_parts=(cur_path/"/")-({""});
        if(test_parts!=parts)
        {
            num_objects_create = strlen(parts)-strlen(test_parts);
            res=create_object(cur_path, parts, num_objects_create);
        }
        return res;
    }
    write("subtracting "+parts[j]+"\n");
    cur_path = cur_path-("/"+parts[j]);
  }
  return 0;
}

int create_object(string path, array(string) parts, int num)
{
    if(path[-1]==47)    //remove last "/"
      path=path[ .. (strlen(path)-2)];
    int i=0;

    object document_factory = _Server->get_factory("Document");
    object container_factory = _Server->get_factory("Container");

    for(i=num; i>0; i--)
    {
      if(i==1)
      {
        mapping map = (["url":path+"/"+parts[i*-1], "mimetype":"text/plain"]);
        object doc = document_factory->execute(map);
        if(doc)
        {
          doc->set_attribute("OBJ_DESC", "from import-from-git");
          return 1;
        }
        else
          return 0;
      }
      else
      {
        object moveloc = OBJ(path);
        string container_name = parts[i*-1];
        object mycont = container_factory->execute((["name":container_name]));
        if(mycont)
        {
            mycont->move(moveloc);
            mycont->set_attribute("OBJ_DESC","from import-from-git");
            path=path+"/"+parts[i*-1];
        }
        else
            return 0;
      }
    }
}

int get_num_versions(string path)
{
  if(path[-1]==47)    //remove last "/"
      path=path[ .. (strlen(path)-2)];
  string dir = dirname(path);
  string filename = basename(path);
  Stdio.File output = Stdio.File();
  write("filename for get_num_versions is "+filename+"\n");
  Process.create_process(({ "git", "rev-list", "HEAD", "--count", filename }), ([ "env":getenv(), "cwd":dir , "stdout":output->pipe() ]))->wait();
  string result = output->read();
  write("number of commits for "+filename+" : "+result+"\n");
  return (int)result;
}

string git_version_content(string path, string ver)
{
    if(path[-1]==47)
       path=path[ .. (strlen(path)-2)];
    string dir = dirname(path);
    string filename = basename(path);
    Stdio.File output = Stdio.File();
    Process.create_process(({ "git", "show", "HEAD~"+ver+":./"+filename }), ([ "env":getenv(), "cwd":dir , "stdout":output->pipe() ]))->wait();
    string result = output->read();
    write("version "+ver+" content is "+result+"\n"); 
    return result;
}
