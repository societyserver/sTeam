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
 * $Id: Task.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Task.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

class Task {
    mapping descriptions;
    object           obj;
    array         params;
    string|function func;
    object          user;
    int              tid; // the id of the task
    int        exec_time; // the time execution should take place
    
    // callback function when a task is done
    void task_done() {
	destruct(this_object());
    }

  void create(void|function f) {
    if ( functionp(f) ) {
      obj = function_object(f);
      obj = obj->this();
      func = function_name(f);
      if ( !obj->find_function(func) )
	func = f;
    }
  }
  object get_user() {
    return user;
  }

  string describe() {
    if ( !objectp(obj) )
      return sprintf("Task(%O), **lost**)",func);
    return sprintf("Task(%O, "+obj->get_identifier()+ "#"+
      obj->get_object_id() + ")", func);
  }

  string _sprintf() {
    return describe();
  }
}

