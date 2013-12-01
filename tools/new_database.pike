/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 */


int main(int argc, array argv)
{
    Sql.Sql handle;
    mapping conf = ([ "rootpw": "", "password": "steam", "user":"steam", 
		      "db":"steam",]);
    for ( int i = 1; i < argc; i++ ) {
      string val;
      
      if ( sscanf(argv[i], "--newroot=%s", val) == 1 ) {
	Process.system("mysqladmin -u root password " + val);
      }
      else if ( sscanf(argv[i], "--password=%s", val) == 1 )
	conf["password"] = val;
      else if ( sscanf(argv[i], "--user=%s", val) == 1 )
	conf["user"] = val;
      else if ( sscanf(argv[i], "--rootpw=%s", val) == 1 )
	conf["rootpw"] = val;
      else if ( sscanf(argv[i], "--db=%s", val) == 1 )
	conf["db"] = val;
      
    }  
    handle = Sql.Sql("mysql://root:"+conf->rootpw+"@localhost/mysql");
    handle->big_query("create database " + conf->db);
    handle->big_query("use mysql");
    handle->big_query("grant all privileges on " + conf->db + ".* to "+
		      conf->user + " @localhost identified by '" + conf->password+
		      "' with grant option;");
    return 0;
}
