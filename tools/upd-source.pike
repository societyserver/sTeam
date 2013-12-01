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
 * $Id: upd-source.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: upd-source.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


void copy_and_link_dir(string source, string target)
{
    array(string) files = get_dir(source);

    foreach(files, string file)
    {
        string newSource = combine_path(source, file);
        string newTarget = combine_path(target, file);
        if (Stdio.is_dir(newSource))
        {
            copy_and_link_dir(newSource, newTarget);
        } else if (Stdio.is_link(newTarget))
        {
            write("skipping backlink "+newTarget+"\n");
        } else if (Stdio.is_file(newSource))
        {
            if (search(file, "~")!=-1)
                write("skipping file "+newSource+"\n");
            else
            {
                write("copy "+newSource+"\n  to "+newTarget+"\n");
                Stdio.cp(newSource, newTarget);
            }
        }
    }
}


int main(int argc, array(string) argv)
{
    string sSourceDir;
    string sTargetDir;
    
    if (argc!=3)
    {
            write("call with \<source-dir\> \<target-dir\>\n"+
                  "notice target-dir must alreay exist\n");
            _exit(0);
    }
    sSourceDir = combine_path(getcwd(), argv[1]);
    sTargetDir = combine_path(getcwd(), argv[2]);

    copy_and_link_dir(sSourceDir, sTargetDir);
}
