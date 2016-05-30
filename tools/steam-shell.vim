command! Steam call Steamshell() 

function! Steamshell()
    execute "tabnew | r! ~/Desktop/sTeamOrig/tools/steam-shell.pike". " ".@*
    silent !clear
endfunction﻿

