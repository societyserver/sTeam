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
 * $Id: maintainance.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: maintainance.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

void http_request(object req)
{
    mapping result = ([ ]);

    werror("Request="+sprintf("%O",req->request_headers)+"\n");
    if ( req->not_query != "/" ) {
        result->file = Stdio.File(req->not_query[1..], "r");
    }
    else {   
    result->data = Stdio.read_file("maintainance.html");
    result->error = 200;
    result->type = "text/html";
    result->len = strlen(result->data);
   } 
    req->response_and_finish(result);
}

int main()
{
    object httpPort = Protocols.HTTP.Server.Port(http_request, 80);
    return -17;
}
