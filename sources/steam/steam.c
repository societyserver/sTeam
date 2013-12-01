#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/param.h>
#include "../../server/include/configure.h"


char * concat ( char * s1, char * s2, char * s3, char * s4 ) {
  char * str;
  int l1, l2, l3, l4;
  l1 = strlen(s1);
  l2 = strlen(s2);
  if ( s3 != NULL ) l3 = strlen(s3);
  else l3 = 0;
  if ( s4 != NULL ) l4 = strlen(s4);
  else l4 = 0;
  str = (char *)malloc( (l1+l2+l3+l4+1) * sizeof(char) );
  strcpy( str, s1 );
  strcat( str, s2 );
  if ( s3 != NULL ) strcat( str, s3 );
  if ( s4 != NULL ) strcat( str, s4 );
  str[l1+l2+l3+l4] = '\0';
  return str;
}

void add_to_env_var ( char * key, char * append1, char * append2 ) {
  char * old;
  char * v;
  char * delimiter;
  old = getenv( key );
  if ( old == NULL || (strlen(old) < 1) ) v = concat( append1, append2, NULL, NULL );
  else v = concat( old, ":", append1, append2 );
  setenv( key, v, 1 );
  free( v );
}

int main ( int argc, char **argv ) {
  char * binary;
  char * binary_path;
  char * path;
  char * dir = NULL;
  char * old_working_dir = NULL;
  char ** args;
  int retval;
  int i;
  int nr_args;
  path = STEAM_DIR;
  binary = BRAND_NAME;
  binary_path = concat( path, "/", binary, NULL );
  add_to_env_var( "PIKE_PROGRAM_PATH", path, "/server" );
  add_to_env_var( "PIKE_INCLUDE_PATH", path, "/server/include" );
  add_to_env_var( "PIKE_MODULE_PATH", path, "/server/libraries" );
  add_to_env_var( "PIKE_MODULE_PATH", path, "/client" );
  args = (char **)malloc( (argc + 2) * sizeof( char* ) );
  args[0] = binary;
  nr_args = 1;
  for ( i=1; i<argc; i=i+1 ) {
    if ( strstr( argv[i], "--dir=" ) != NULL ) {
      dir = argv[i] + strlen("--dir=")*sizeof(char);
      old_working_dir = (char *)malloc( (MAXPATHLEN+1)*sizeof(char) );
      getcwd( old_working_dir, MAXPATHLEN );
      chdir( dir );
      continue;
    }
    args[nr_args] = argv[i];
    nr_args = nr_args + 1;
  }
  args[nr_args] = NULL;
  retval = execv( binary_path, args );
  if ( old_working_dir != NULL ) {
    chdir( old_working_dir );
    free( old_working_dir );
  }
  free( args );
  free( binary_path );
  return retval;
}
