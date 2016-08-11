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
"Register % stores the value of current file from where the command is executed and adding -disp "opens it's log file.
    execute "tabe %-disp | r! /usr/local/lib/steam/tools/steam-shell.pike". " ".@0
    silent !clear
endfunction﻿

function! Open(name)
	
	"pike code to fetch and store the contents of the file in a temporary file

	let code = 'inherit "/usr/local/lib/steam/tools/applauncher.pike";string open(){string fullpath="'.a:name.'";string pathfact=_Server->get_factory(OBJ(fullpath))->query_attribute("OBJ_NAME");if (pathfact \!= "Document.factory") {write("you can not edit this file.");return 0;}object obj = OBJ(fullpath);object xslobj;if(obj->get_identifier()[sizeof(obj->get_identifier())-8..]==".xsl.xml"){string xslnamex=obj->get_identifier()[..sizeof(obj->get_identifier())-9]+ ".xsl";xslobj=obj->get_environment()->get_object_byname(xslnamex);}string content = obj->get_content();string dir;dir="/tmp/"+(MIME.encode_base64(Crypto.Random.random_string(10), 1)-("/"))+System.getpid();mkdir(dir,0700);string filename=obj->get_object_id()+"-"+obj->get_identifier();filename=dir+"/"+filename;string debugfilename=filename+"-disp";Stdio.write_file(filename,content||"",0600);Stdio.write_file(debugfilename,"This is your log window\n",0600);send_message(sprintf("(opened \%O \%s)\n", obj,filename),debugfilename);vim_upload(({filename}),({obj}),({xslobj}));return filename;}open();'
	
	"store the result of execution of pike script
	execute "tabnew |r! /usr/local/lib/steam/tools/steam-shell.pike"." '".code."'"
	silent !clear
	"extract the file name from the result
	"copy the results of pike script to the variable result
	let @a=''
	%ya
	let result = @a
	"search for Result: and copy that line to register A
	let @a=''
	g/Result:/y A
	let result = @a
	"split the line based on space, the name of the file is the second element
	let x = split(result,"\"")
	"close the file containing the result of the pike script
	q!
	execute("tabnew ".x[1]."-disp"."|sp ".x[1])
	
	let g:path=a:name
endfunction

function! Upload()
	"upload needs to be implemented
	write
	if exists("g:path")
		let code = 'inherit "/usr/local/lib/steam/tools/applauncher.pike";string filename="'.@%.'";object obj=OBJ("'.g:path.'");object xslobj;if(obj->get_identifier()[sizeof(obj->get_identifier())-8..]==".xsl.xml"){string xslnamex=obj->get_identifier()[..sizeof(obj->get_identifier())-9]+ ".xsl";xslobj=obj->get_environment()->get_object_byname(xslnamex);}vim_upload(({filename}),({obj}),({xslobj}));'
		execute "! /usr/local/lib/steam/tools/steam-shell.pike"." '".code."'"
		silent !clear
	endif
endfunction

	 
