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
    ({"force",Getopt.NO_ARG,({"-F","--force"})}),
    ({"bestoption",Getopt.NO_ARG,({"-B","--bestoption"})}),
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
    int a=0;
    write("inside import-from-git function\n");
    int i;
    if(check_steam_path(to)&&check_from_path(from))
    {
       write("steam path and from path are correct\n");
       int num_versions = get_num_versions(from);
       write("inside main : num_versions : "+(string)num_versions+"\n");
       array steam_history = get_steam_versions(OBJ(to));

      if(options->bestoption)
      {
          string best = show_bestoption(from, to, steam_history, num_versions);
          write("Best option : "+best+"\n");
      }
      else
      {
       if(options->append)
        a = handle_append(from, to, steam_history, num_versions);
       else if(options->force)
        a = handle_force(from, to, num_versions);
       else
        a = handle_normal(from, to, 1, steam_history, num_versions);

        if(a)
        {
          write("Succesfully imported\n");
        }
        else
        {
          write("import failed\n");
        }
      }
    }
}



array get_steam_versions(object obj)
{
  mapping versions = obj->query_attribute("DOC_VERSIONS");
  if (!sizeof(versions))
  {
    versions = ([ 1:obj ]);
  }
  array this_history = ({});
  foreach(versions; int nr; object version)
  {
    this_history += ({ ([ "obj":version, "version":nr, "time":version->query_attribute("DOC_LAST_MODIFIED"), "path":obj->query_attribute("OBJ_PATH") ]) });
  }
  sort(this_history->version, this_history);
  if(strlen(versions)>1)
      this_history += ({ ([ "obj":obj, "version":this_history[-1]->version+1, "time":obj->query_attribute("DOC_LAST_MODIFIED"), "path":obj->query_attribute("OBJ_PATH") ]) });
  return this_history;
}


int check_from_path(string path)
{
  if(path[-1]==47)    //remove last "/"
      path=path[ .. (strlen(path)-2)];

  string dir,filename;

  write("Came inside check_from_path\n");
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
    if(cont||(cur_path==""))  //cur_path check for root-room
    {
        write("Got correct path as : "+cur_path+"\n");
        test_parts=(cur_path/"/")-({""});
        if(test_parts!=parts)
        {
            num_objects_create = strlen(parts)-strlen(test_parts);
            res=create_object(cur_path, parts, num_objects_create);
        }
        write("returning the object from check_steam_path\n");
        return 1;
    }
    else
    {
        if((strlen(parts)==1)&&(parts[0]!="home"))
        {
          res = create_object("/", parts, 1);
          return 1;
        }
    write("subtracting "+parts[j]+"\n");
    cur_path = cur_path-("/"+parts[j]);
    }
  }
  write("returning 0 from check_steam_path\n");
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

string git_version_content(string path, string ver, int total)
{
    write("ver passed is : "+ver+"\n");
    write("total passed is : "+total+"\n");
    ver=(string)(total-((int)ver-1)-1);
    write("ver is now : "+ver+"\n");
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

int handle_append(string from, string to, array steam_history, int num_git_versions)
{
    write("inside handle append\n");
    string scontent = steam_history[strlen(steam_history)-1]->obj->get_content();
    string gcontent = git_version_content(from,(string)1,num_git_versions);
    write("scontent : "+scontent+"\n");
    write("gcontent : "+gcontent+"\n");
    if(scontent==gcontent)
    {
     int i=0;
     for(i=2;i<=num_git_versions;i++)
     {
      string content = git_version_content(from,(string)i, num_git_versions);
      OBJ(to)->set_content(content);
     }
     return 1;
    }
    return 0;
}


int handle_force(string from, string to, int num_git_versions)
{
    int i=0;
    for(i=1;i<=num_git_versions;i++)
    {
     string content = git_version_content(from,(string)(i), num_git_versions);
     OBJ(to)->set_content(content);
    }
    return 1;
}

int handle_normal(string from, string to, int num, array steam_history, int num_git_versions)
{
  string scontent = steam_history[num-1]->obj->get_content();
  write("STEAM HISTORY IS : %O\n and number is %d",steam_history,num-1);
  string gcontent = git_version_content(from,(string)(num),num_git_versions);


  if((num>strlen(steam_history))||((num==1)&&!scontent))   //after successful history, add it to steam. (second condition for object in sTeam with no versions).
  {
    int i=0;
    for(i=num;i<=num_git_versions;i++)
    {
     string content = git_version_content(from,(string)(i), num_git_versions);
     OBJ(to)->set_content(content);
    }
    return 1;
  }
  write("Comparing\n");
  write("scontent : "+scontent+"\n");
  write("gcontent : "+gcontent+"\n");
  if(scontent==gcontent)
  {
    write("Equal\n");
    return handle_normal(from, to, num+1, steam_history, num_git_versions);
  }
  else
  {
    write("Not Equal\n");
    write("Exiting from script. Commits and versions dont match\n");
    return 0;
  }
}

string show_bestoption(string from, string to, array steam_history, int num_git_versions)
{
  //CHECKING FOR NORMAL
  int i=0,flag=0;
  string scontent,gcontent;
  for(i=1;i<=strlen(steam_history);i++)
  {
    scontent = steam_history[i-1]->obj->get_content();
    gcontent = git_version_content(from,(string)i,num_git_versions);
    if(scontent!=gcontent)
    {
        flag=1;
        break;
    }
  }
  if(flag==0)
      return "normal";

  //CHECKING FOR APPEND
  scontent = steam_history[strlen(steam_history)-1]->obj->get_content();
  gcontent = git_version_content(from,(string)1,num_git_versions);
  if(scontent==gcontent)
      return "append(-A)";
  else  //OTHERWISE FORCE OPTION
      return "force(-F)";
}
