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
 * $Id: db_timeout.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: db_timeout.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

Sql.Sql db_handle;
Calendar.ISO cal = Calendar.ISO->set_language("german");

void test_connect(int time)
{
    werror(sprintf("%s: (%d) connecting database - ",
                   cal->Second()->format_nice(), time));
    string erg = db_handle->host_info();
    werror("("+erg+")");
    Sql.sql_result res = db_handle->big_query("select ob_id, ob_class from "+
                                              "objects where ob_id = "+
                                              (random(17)+2));

    string sId, sClass;

    [sId, sClass] = res->fetch_row();
    werror(sprintf(" [%s, %s]\n", sId, sClass));
    call_out(test_connect, 2*time, 2*time);
}

int main() {
    db_handle = Sql.Sql("mysql://balduin:steam?mysql@localhost/balduinDev");
    call_out(test_connect,1 ,1);
    return -1;
}
