inherit Service.Service;

void call_service(object user, mixed args, int|void id)
{
    string texcode ="\\documentclass[10pt]{article}\n\\pagestyle{empty}\n\\usepackage{amsmath}\n\\usepackage{amsfonts}\n\\usepackage{amssymb}\n\\usepackage{pst-plot}\n\\usepackage{color}\n\\usepackage{pstricks}\n\\parindent=0pt\n\\begin{document}\n";

    string formula = args->formula;
    if ( stringp(formula) ) {
	texcode += "$" + String.trim_all_whites(formula) + "$\n";
    }
    texcode += "\\end{document}\n";
    
    // run tex
    rm("in.dvi");
    werror("running process tex...\n");
    Stdio.File texfile = Stdio.File("in.tex", "wct");
    texfile->write(texcode);
    texfile->close();
    array runArr = ({ "latex", "-interaction=nonstopmode", "in.tex" });
    array psArr = ({ "dvips", "-R", "-E", "in.dvi", "-f" });
    array convArr = ({ "convert", "-quality", "100", "-density","120", "-transparent", "white", "in.ps", "formula.png" });
    object errFile = Stdio.File("in.log", "wct");
    Stdio.File ipc = Stdio.File();
    werror(texcode + "\n");
    Process.create_process( runArr, ([ "env": getenv(), "cwd": getcwd(), 
				       "stdout": errFile, "stderr": errFile, ]) )->wait();
    Stdio.File psFile = Stdio.File("in.ps", "wct");
    Process.create_process( psArr, ([ "env": getenv(), "cwd": getcwd(), 
				       "stdout": psFile, "stderr": errFile, ]) )->wait();
    psFile->close();
    Process.create_process( convArr, ([ "env": getenv(), "cwd": getcwd(), 
				       "stdout":errFile, "stderr": errFile, ]) )->wait();
    errFile->close();
    rm("in.tex");
    rm("in.log");
    rm("in.ps");
    rm("in.dvi");
    string res;
    res = Stdio.read_file("formula.png");
    async_result(id, res);
}

static void run() {
}

static private void got_kill(int sig) {
	_exit(1);
}

int main(int argc, array argv)
{
	signal(signum("QUIT"), got_kill);
	init( "tex", argv );
        start();
	return -17;
}

