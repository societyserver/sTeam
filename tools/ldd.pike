string sandbox = "";

int main(int argc, array argv)
{
  Stdio.File t;
  Stdio.File stdin = Stdio.File();
  Stdio.File stdout = Stdio.File();
  
    mapping options = ([
      "stdout":(t=stdout->pipe()), /* Stdio.PROP_IPC| Stdio.PROP_NONBLOCKING */
      "stderr":t,
      "cwd": "/",
      "noinitgroups":1,
    ]);
    sandbox = argv[2];
    stdout->set_nonblocking(read_ldd, 0, done);
    Process.create_process( ({ "ldd", argv[1] }), options);
    return -17;
}

void done(mixed ctx)
{
  exit(0);
}

void read_ldd(mixed ctx, string data)
{
  string file;
  while ( sscanf(data, "%*s => %s (%*s)\n%s", file, data) > 0 )
    Process.system("cp " + file + " "+ sandbox + file);
}
