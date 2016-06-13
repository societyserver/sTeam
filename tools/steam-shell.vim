command! Steam call Steamshell() 
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

