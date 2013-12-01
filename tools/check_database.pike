/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: check_database.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: check_database.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

string db_connect;
string config_file = "config/config.txt.steam";
Sql.Sql handle;

int naming = 0;
int verbose = 0;
int analyse = 1;

#define NEED_ARGS(s) if (!arg) { write("--"+(string)s+" needs an argument passed\n");return;}

int get_variable(string name)
{
    object res;
    res = db()->big_query("select value from variables where "+
                          "var =\""+name+"\"");
    if (objectp(res) && res->num_rows())
        return (int) res->fetch_row()[0];
    
    return 0;
}

string read_config(string filename, string param)
{
    string config = Stdio.read_file(filename);    
    string acc_str;
    sscanf(config, "%*s<"+param+">%s</"+param+">%*s", acc_str);
    if (verbose)
        write(sprintf("reading config file %s accessing %s\n",
                      filename, acc_str));
    return acc_str;
}

Sql.Sql db() {
    if (objectp(handle))
        return handle;
    handle = Sql.Sql(db_connect);
    return handle;
}


int detect() {
    int iObjectsId = get_variable("#objects");
    int status = 0;

    // check for existing differing tables
    if (sizeof(db()->list_tables("i_"+(string)iObjectsId)))
        status |= 1;
    if (sizeof(db()->list_tables("i_objects")))
        status |= 2;

    // we have both objects and i_oid_alias
    if (status == 3)
    {
        Sql.sql_result
            res = db()->big_query("select v from i_objects "+
                                  "where k=\"rootroom\"");
        string id_objects = res->fetch_row()[0];
        res = db()->big_query("select v from i_"+
                              (string)iObjectsId+" where k="+
                              "\"rootroom\"");
        string id_ioid = res->fetch_row()[0];
        
        if ( ((int) id_objects[1..]) < ((int) id_ioid[1..]))
        {
            naming = 1;
            status = 4;
        }
        else
            status = 5;
    }

    if (verbose)
        write(sprintf("Object ID of module objects is %d status %d\n",
                      iObjectsId, status));
    // i_objects found without alternatives, thus naming is 1, but are
    // there other strange modules?
    if (status == 2)
    {
        naming = 1;
        Sql.sql_result res =
            db()->big_query("select var, value from variables where var "+
                            "like \"#%\"");
        string var, value;
        mixed vec;
        while (vec = res->fetch_row())
        {
            [var, value] = vec;
            if (sizeof(db()->list_tables("i_"+value)))
                return 6; // at least one module with aliases
        }
    }
    return status;
}




void main(int argc, array(string) argv)
{
    for (int i=1;i <sizeof(argv); i++) {
        string cmd, arg;
        if (sscanf(argv[i], "--%s=%s", cmd, arg) ==2 ||
            sscanf(argv[i], "--%s", cmd))
        {
            switch (cmd) {
              case "detect" :
                  if (!db_connect)
                      db_connect = read_config(config_file,"database");
                  switch (detect()) {
                    case 0:
                        write("no tables found -> unable to repair!\n");
                        break;
                    case 1:
                        write("no table i_objects -> rename i_oid tables.\n");
                        break;
                    case 2:
                        write("i_objects exists and there is no alternative "+
                              "table -> everything seems to be ok!\n");
                        break;
                    case 3:
                        write("huh? differing tables exist, but couldn't "+
                              "decide.\n");
                        break;
                    case 4:
                        write("differing tables found i_objects seems to be "+
                              "the original -> deleting i_oid files.\n");
                        write(sprintf("naming %d\n",naming));
                        break;
                    case 5:
                        write("differing tables found i_oid seems to be "+
                              "the original -> moving values.\n");
                    case 6:
                        write("i_objects exists and has no alternative, but "+
                              "there are other broken modules.\n");
                        break;
                  }
                  return;
              case "db":
              case "database":
                  NEED_ARGS("database");
                  db_connect = arg;
                  break;
              case "with-config":
                  NEED_ARGS("with-config");
                  config_file = arg;
              case "auto":
                  db_connect = read_config(config_file,"database");
                  break;
              case "verbose":
              case "v":
                  verbose = 1;
                  break;
              case "fix":
                  analyse = 0;
                  break;
            }
        }
    }

    if (!db_connect)
        db_connect = read_config(config_file, "database");

    detect();
    
    Sql.sql_result modules =
        db()->big_query("select var, value from variables where var "+
                        "like \"#%\"");

    string var, value;
    mixed vec;
    array temp = ({ ({ "#modules", "0" }) });
    while (vec = modules->fetch_row())
        temp += ({ vec });

    foreach (temp, vec)
    {
        int status = 0;
        [var, value] = vec;
        if (search(db()->list_tables("i_"+value), "i_"+value)!=-1)
            status |=1;
        if (search(db()->list_tables("i_"+var[1..]), "i_"+var[1..])!=-1)
            status |=2;

        switch (status) {
          case 1:
              write(sprintf("rename i_%s to i_%s\n", value, var[1..]));
              if (!analyse)
              {
                  db()->big_query(sprintf("alter table i_%s rename to i_%s",
                                          value, var[1..]));
              }
              break;
          case 2:
              write(sprintf("keep i_%s\n", var[1..]));
              break;
          case 3:
              if (naming ==1) // heuristics is from table i_objects
              {
                  write(sprintf("conflict keep i_%s and "+
                                "delete i_%s\n",
                                var[1..], value));
                  if (!analyse)
                  {
                      db()->big_query(sprintf("drop table i_%s", value));
                  }
              }
              else
              {
                  write(sprintf("conflict move values from i_%s to"+
                                " i_%s\n", value, var[1..]));
                  if (!analyse)
                  {
                      db()->big_query(sprintf("drop table i_%s", var[1..]));
                      db()->big_query(sprintf("alter table i_%s rename "+
                                              "to i_%s", value, var[1..]));
                  }
              }
              break;
        }
              
    }
}

