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
 * $Id: gtklogin.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: gtklogin.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


void do_login(array w, object widget)
{
  string name = w[1]->get_text();
  string passwd = w[2]->get_text()||"";
  
  if(w[3](name, passwd, @w[4..] )) // login successfull
  {
    w[0]->unmap();
    destruct(w[0]);
  }
  else
    GTK.Alert("login failed");
}

string _(string message)
{
  return message;
}

void get_login(string label, string username, mixed ... args)
{

  werror("get_login, %O\n", args);
  object pwin, plabel, pentry, llabel, lentry;
  object pbox, lbox, ok, cancel, vbox, frame, bbox;
  object tbox;

  pwin = GTK.Window( GTK.WINDOW_TOPLEVEL );
  pwin->realize();
  pwin->set_policy(1,1,0);
  pwin->set_title(_("sTeam application launcher ")+label);
  pwin->set_usize(300, 150);
  frame = GTK.Frame(_("Enter login for ")+label);

  llabel = GTK.Label(_("Username:  "));
  lentry = GTK.Entry();
  vbox = GTK.Vbox(0,0);
  vbox->border_width(5);
  vbox->set_spacing(5);

  lbox = GTK.Hbox(0,0);
  lbox->pack_start(llabel,0,0,0);
  lbox->pack_end(lentry,1,1,1);
  vbox->pack_start(lbox,0,0,0);

  username && lentry->set_text(username);
  plabel = GTK.Label(_("Password:  "));
  pentry = GTK.Entry();
  pentry->set_visibility(0);
  pbox = GTK.Hbox(0,0);
  pbox->pack_start(plabel,0,0,0);
  pbox->pack_end(pentry,1,1,1);
  vbox->pack_start(pbox,0,0,0);

  !username&&lentry->signal_connect("activate", do_login, 
                                    ({ pwin, lentry, pentry, @args }));
  pentry->signal_connect("activate", do_login, 
                         ({ pwin, lentry, pentry, @args }));
  ok = GTK.Button(_("Login"));
  cancel = GTK.Button(_("Cancel"));
  ok->signal_connect("clicked", do_login, ({ pwin, lentry, pentry, @args }));

  cancel->signal_connect("clicked", exit, 0);

  bbox = GTK.HbuttonBox();
  bbox->set_spacing(4)
    ->set_layout(GTK.BUTTONBOX_SPREAD)
    ->pack_start(ok, 0,0,0)
    ->pack_end(cancel, 0,0,0);

  vbox->pack_end(bbox,0,0,0);
   
  frame->add(vbox);
  frame->border_width(5);

  tbox = GTK.Vbox(0,0);
  tbox->pack_start(frame, 1,1,1);
  pwin->add(tbox);
  pwin->show_all();
}

