command! Steam call Steamshell()
command! -nargs=1 Open call Open(<f-args>)
command! Upload  call Upload()
autocmd BufWritePost * Upload
"Note: This file needs to be included in the applauncher.pike in the function call edit(array(object))
"Function Usage
"Enter the Vi insert mode (i) and type the commands
"Enter the Vi visual mode(v). Select the command using the Vi Visual mode.
"Now type : y To yank the text
"Now enter the command Steam
"It would prompt you to enter steam password. After this the output of the command shall be displayed in a the log buffer which would be opened in a new tab.

function! Steamshell()
"tab sb 2 displays the contents of the buffer 2 in a new tab.
"In this case the buffer 2 stands for the log buffer.
"In future if a vim script is included the buffer number should be noted down for the log buffer using :ls and the below command should be modified to include the changes in it.
"The contents selected in the Vi visual mode are savied in the "* register. The contents of this register are appended as an argument to the command which is simulated using execute command.
"r!  Execute {cmd} and insert its standard output below the cursor or the specified line. 
    let @0 = substitute(@0, '\n', " ", "g")
    execute "tab sb 1 | r! /usr/local/lib/steam/tools/steam-shell.pike". " '".@0."'"
    silent !clear
endfunction﻿

function! Open(name)
	let code = 'string open(){string fullpath="'.a:name.'";string pathfact=_Server->get_factory(OBJ(fullpath))->query_attribute("OBJ_NAME");if (pathfact \!= "Document.factory") {write("you can not edit this file.");return 0;}Object obj = OBJ(fullpath);string content = obj->get_content();string dir;dir="/tmp/"+(MIME.encode_base64(Crypto.Random.random_string(10), 1)-("/"))+System.getpid();mkdir(dir,0700);string filename=obj->get_object_id()+"-"+obj->get_identifier();filename=dir+"/"+filename;string debugfilename=filename+"-disp";Stdio.write_file(filename,content||"",0600);Stdio.write_file(debugfilename,"This is your log window\n",0600);return filename;}open();'
	
	execute "tabnew |r! /usr/local/lib/steam/tools/steam-shell.pike"." '".code."'"
	silent !clear
	%y+
	let result = @+
	let @a=''
	g/Result:/y A
	let result = @a
	let x = split(result,"\"")
	q!
	execute("tabnew ".x[1]."-disp"."|sp ".x[1])
endfunction

function! Upload()
	echo "uploading"
endfunction

	 
