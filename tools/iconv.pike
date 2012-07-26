int fix_object_content(object o, string encoding)
{   
    string old = o->get_content();
    return o->set_content(conv(([ "content":old, "charset":encoding ]))) - sizeof(old);
}

string conv(mapping data)
{ 

    if (!data->charset || !data->content)
        return 0;
  
    array command = ({ "iconv", "-f", data->charset, "-t", "UTF8" });
    Stdio.File mystdin = Stdio.File();
    Stdio.File mystdout = Stdio.File();
    Stdio.File mystderr = Stdio.File();
    Stdio.File stdinpp = mystdin->pipe();
    Stdio.File stdoutpp = mystdout->pipe();
    Stdio.File stderrpp = mystderr->pipe();
  
  
    object p = Process.create_process(command, ([
                         "stdin" :stdinpp,
                         "stdout":stdoutpp,
                         "stderr":stderrpp,
                           ]));
    mixed res = mystdin->write(data->content);
    mystdin->close();
    p->wait();
    string out = "";
    while(mystdout->peek())
    {   
        out += mystdout->read(10000, 1);
    }
    return out;
    //return utf8_to_string(out);
}

