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
 * $Id: tasks.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: tasks.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";

inherit "/kernel/module";

import Task;

#include <macros.h>
#include <exception.h>
#include <attributes.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <config.h>


#ifdef TASK_DEBUG
#define DEBUG_TASK(s, args...) write("TASKS: "+s+"\n", args)
#else
#define DEBUG_TASK(s, args...)
#endif

static mapping mTasks = ([ ]);
static int            tid = 0;
static Thread.Queue taskQueue; // task Queue

object log;

void task_debug(string s)
{
    if ( objectp(log) ) {
	string l = log->get_content();
	log->set_content(l+ "On "+ctime(time())+": &nbsp;&nbsp;"+ s+"<br/>");
    }
}


void init_module()
{
    add_data_storage(STORE_TASKS,retrieve_tasks, restore_tasks);
    taskQueue = Thread.Queue();

    start_thread(worker); // start 1 worker threads

}

void worker()
{
    while ( 1 ) {
      mixed err = catch {
	object task = taskQueue->read();
	string tdescribe = task->describe();
	float tt = gauge(f_run_task(task));
	int slow = (int)_Server->get_config("log_slow_tasks");
	if ( slow && (int)(tt*1000.0) > slow )
	  get_module("log")->log("slow_requests", LOG_LEVEL_INFO, 
				 "%s Task %s took %d ms", 
				 timelib.event_time(time()), tdescribe,
				 (int)(tt*1000.0));
      };
      if ( err ) {
	if ( arrayp(err) && sizeof(err) == 3 && (err[2] & E_ACCESS) ) {
	  get_module("log")->log("security", LOG_LEVEL_DEBUG, "%O\n%O",
				 err[0], err[1]);
	}
	else
	  FATAL("Task failed with error: %O\n%O", err[0], err[1]);
      }
      else {
	DEBUG_TASK("Task succeeded !");
      }
    }
}

mapping retrieve_tasks()
{
    if ( CALLER != _Database )
	THROW("Caller is not database !", E_ACCESS);
    mapping save = ([ ]);
    foreach ( indices(mTasks), mixed idx)
      if ( objectp(idx) ) {
        save[idx] = ({});
        foreach(mTasks[idx], object t ) {
          if ( objectp(t) && !functionp(t->func) && objectp(t->obj))
            save[idx] += ({ mkmapping(indices(t), values(t)) });
        }
      }
    //werror("****** retrieve_tasks() = %O\n", save);
    return ([ "tasks": save, "id": tid, ]);
}

void restore_tasks(mapping data)
{
    if ( CALLER != _Database )
	THROW("Caller is not database !", E_ACCESS);
    foreach(indices(data["tasks"]), object o ) {
	foreach(data["tasks"][o], mapping m)
	{
	    LOG("Task="+sprintf("%O\n",m));
	    object t = add_task(o, m->obj, m->func, 
				m->params, m->descriptions);
	}
    }
    tid = data->id;
}


/**
 * Add a task for a user or a general task. The task will be execute when
 * the user logs in or after a time of t.
 *  
 * @param object|int user_t - a user task, ask the user upon login
 * @param object obj - the object to call a function 
 * @param string func - the task function to call
 * @param array args
 * @return the resulting task object (see Task.pmod)
 */
object 
add_task(int|object user_t, object obj, string|function func, array args, mapping desc)
{
    object task = Task();
    task->obj = obj;
    task->func = func;
    task->params = args;
    task->descriptions = desc;
    task->tid = ++tid;
    task->exec_time = 0;

    mTasks[tid] = task;

    // user related task
    if ( objectp(user_t) ) {
	if ( !arrayp(mTasks[user_t]) )
	    mTasks[user_t] = ({ });
	mTasks[user_t] += ({ task });
	// do not save these tasks
        run_task(task);
    }
    else {
	task->exec_time = user_t;
	if ( task->exec_time > time() ) {
            DEBUG_TASK("New Task running later !");
	    call(run_task, time() - task->exec_time, task);
	}
	else {
	    run_task(task);
	    DEBUG_TASK("New Task immediate execution !");
	}
	// execute immediately or after time user_t
    }
    
    DEBUG_TASK("added %O (id="+task->tid+")", func);
    require_save(STORE_TASKS);
    
    return task;
}

array get_tasks(object user)
{
  array tasks = mTasks[user] || ({ });
  return tasks - ({ 0 });
}


object get_task(int tid)
{
    return mTasks[tid];
}

mapping _get_tasks()
{
    return mTasks;
}

void tasks_done(object user)
{
    DEBUG_TASK("All Tasks done for "+ user->get_identifier());
    mTasks[user] = ({ });
    require_save(STORE_TASKS);
}

static void f_run_task(object t)
{
    function f;
    mixed  err;
    
    DEBUG_TASK("Tasks: looking for %O\n", t->func);
    if ( !functionp(t->func) ) {
      if ( !objectp(t->obj) ) {
	FATAL("Invalid Task %O\n", t->describe());
        m_delete(mTasks, t->tid);
        require_save(STORE_TASKS);
	return;
      }
      f = t->obj->find_function(t->func);
    }
    else
      f = t->func;

    if ( !functionp(f) ) {
	FATAL("Cannot find task '"+t->func+"' to execute !");
	return;
    }
    DEBUG_TASK("Running task " + t->tid + "(%O in %O) as %O\n", 
               t->func, 
               t->obj,
               t->user);
    DEBUG_TASK("Current user is %O", this_user());
    
   
    seteuid(t->user);
    if ( arrayp(t->params) ) 
	err = catch(f(@t->params));
    else
	err = catch(f());

    if ( err != 0 ) {
	FATAL( "Error while running task (%O in %O) as %O: %O\n%O",
               t->func, t->obj, t->user, err[0], err[1] );
    }

    DEBUG_TASK("Task " + t->tid + " success !");
    m_delete(mTasks, t->tid);
    err = catch(t->task_done());
    if ( err != 0 )
	FATAL( "Error while ending task (%O in %O) as %O: %O",
               t->func, t->obj, t->user, err );

    require_save(STORE_TASKS);
}

int run_task(int|object tid)
{
    object t;
    if ( !objectp(tid) )
	t = mTasks[tid];
    else
	t = tid;

    if ( !objectp(t) ) {
	FATAL("Unable to perform task " + tid + ": no object.");
	return 0;
    }
    
    t->user = geteuid() || this_user();
    DEBUG_TASK("Run Task %O in %O (id=%d) as %O", 
               t->func, 
               t->obj, 
               t->tid,
               t->user);


    taskQueue->write(t);
    return 1;
}

string get_identifier() { return "tasks"; }

void create_group_exit(object grp, object user)
{
    object dest = grp->query_attribute(GROUP_WORKROOM);
    object wr = user->query_attribute(USER_WORKROOM);
    array exits = wr->get_inventory_by_class(CLASS_EXIT);
    
    // check if exit already exists in workarea
    foreach ( exits, object ex )
	if ( ex->get_exit() == dest )
	    return;


    object factory = _Server->get_factory(CLASS_EXIT);
    object exit = factory->execute(
	([ "name": grp->parent_and_group_name() + " workarea", "exit_to": dest, ]) );
    exit->sanction_object(this(), SANCTION_ALL);
    exit->move(wr);
}

void join_invited_group(object grp, object user)
{
    grp->add_member(user);
    create_group_exit(grp, user);
}

void remove_group_exit(object grp, object user)
{
    object wr = user->query_attribute(USER_WORKROOM);
    if ( objectp(wr) ) {
	foreach(wr->get_inventory_by_class(CLASS_EXIT), object exit)
	    if ( exit->get_exit() == grp->query_attribute(GROUP_WORKROOM) )
	    {
		exit->delete();
		return;
	    }
    }
}
