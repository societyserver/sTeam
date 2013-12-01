#!/usr/bin/pike

// default authors:
array authors = ({
  "Robert Hinn <exodus@uni-paderborn.de>",
  "Thomas Bopp <astra@uni-paderborn.de>",
  "Daniel Buese <dbuese@uni-paderborn.de>",
});


string wrap_string ( string str, int width, void|string bullet ) {
  string result = "";
  array words = str / " ";
  string line = "";
  string indentation = "";
  if ( stringp(bullet) && sizeof(bullet) ) {
    line = bullet;
    indentation = " " * sizeof(bullet);
  }
  foreach ( words, string word ) {
    if ( sizeof(line) + 1 + sizeof(word) <= width ) line += " " + word;
    else {
      result += line + "\n";
      line = indentation + " " + word;
    }
  }
  if ( sizeof(line) && line != indentation ) result += line;
  return result;
}


int main ( int argc, array argv ) {

  string config_h = "server/include/config.h";
  string doxyfile = "Doxyfile";
  string suse_spec = "distrib/suse/steam.spec";
  array debian_changelogs = ({ "debian/changelog",
                                 "distrib/debian-3.1/changelog" });
  array other_changelogs = ({ "CHANGELOG" });

  // find current version:
  array lines;
  catch ( lines = Stdio.read_file( config_h ) / "\n" );
  if ( !arrayp(lines) ) lines = ({ });
  string old_version;
  int line_nr;
  for ( line_nr=0; line_nr<sizeof(lines); line_nr++ ) {
    sscanf( lines[line_nr],
            "%*[ \t]#define%*[ \t]STEAM_VERSION%*[ \t]\"%s\"%*[ \t]",
            old_version );
    if ( stringp(old_version) && sizeof(old_version) != 0 )
      break;
  }
  if ( !stringp(old_version) || sizeof(old_version) == 0 ) {
    werror( "* Error: Could not find current version number in "
            + config_h + " !\n" );
    exit( 1 );
  }

  // ask for new version:
  string propose_version = "unknown";
  array version_parts = old_version / ".";
  catch {
    version_parts[-1] = (string)(((int)version_parts[-1]) + 1);
    propose_version = version_parts * ".";
  };
  write( "Old open-sTeam version: %s\n", old_version );
  write( "Please enter the new version [" + propose_version + "] : " );
  string new_version = Stdio.stdin.gets();
  if ( !stringp(new_version) || sizeof(new_version) == 0 )
    new_version = propose_version;

  // ask for changelog:
  write( "Please enter the changelog for version %s :\n", new_version );
  write( "(Just enter plain text without any bullets or formating. A new line "
         + "will\nbegin the next changelog entry, an empty line will end the"
         + "changelog.)\n" );
  array changelog = ({ });
  do {
    write( "entry #" + (sizeof(changelog)+1) + " : " );
    string line = Stdio.stdin.gets();
    if ( !stringp(line) || sizeof(line) == 0 )
      break;
    changelog += ({ line });
  } while ( 1 );

  // author:
  write( "Please enter the author information or choose an author by entering "
         + "\nhis or her number from the following list:\n" );
  for ( int i=0; i<sizeof(authors); i++ )
    write( "" + (i+1) + " : " + authors[i] + "\n" );
  write( "Author [" + authors[0] + "] : " );
  string author = Stdio.stdin.gets();
  if ( !stringp(author) || sizeof(author) == 0 )
    author = authors[0];
  else {
    int author_nr;
    catch( author_nr = (int)author );
    if ( author_nr > 0 ) author = authors[author_nr];
  }
  string author_name, author_email;
  sscanf( author, "%s <%s>", author_name, author_email );
  if ( !stringp(author_name) || sizeof(author_name) == 0 ||
       !stringp(author_email) || sizeof(author_email) == 0 ||
       search( author_email, "@" ) < 0 ) {
    werror( "* Error: invalid author information: %s\n  Must be: "
            + "\"Name <email>\" !\n", author );
    exit( 1 );
  }

  // preview:
  write( "\nWill create version %s\nChangelog:\n", new_version );
  foreach( changelog, string entry ) {
    write( wrap_string( entry, 78, "*" ) + "\n" );
  }
  write( "Author: " + author + "\n" );
  write( "\nCreate this version? [y] " );
  string answer = Stdio.stdin.gets();
  if ( stringp(answer) && sizeof(answer) && lower_case(answer) != "y" &&
       lower_case(answer) != "yes" ) {
    write( "Aborted.\n" );
    exit( 1 );
  }

  // update version:
  // server/include/config.h:
  lines[line_nr] = "#define STEAM_VERSION \"" + new_version + "\"";
  write( "Updating " + config_h + " ...\n" );
  Stdio.write_file( config_h, (lines * "\n")+"\n" );
  // Doxyfile:
  write( "Updating " + doxyfile + " ...\n" );
  catch ( lines = Stdio.read_file( doxyfile ) / "\n" );
  if ( !arrayp(lines) ) lines = ({ });
  string doxy_version;
  for ( line_nr=0; line_nr<sizeof(lines); line_nr++ ) {
    sscanf( lines[line_nr],
            "%*[ \t]PROJECT_NUMBER%*[ \t]=%*[ \t]%s%*[ \t]",
            doxy_version );
    if ( stringp(doxy_version) && sizeof(doxy_version) != 0 )
      break;
  }
  if ( !stringp(doxy_version) || sizeof(doxy_version) == 0 )
    werror( "* Warning: Could not find old version number in "
            + doxyfile + " !\n" );
  else {
    lines[line_nr] = "PROJECT_NUMBER         = " + new_version;
    Stdio.write_file( doxyfile, (lines * "\n")+"\n" );
  }
  // SUSE spec file:
  write( "Updating " + suse_spec + " ...\n" );
  catch ( lines = Stdio.read_file( suse_spec ) / "\n" );
  if ( !arrayp(lines) ) lines = ({ });
  string suse_version;
  for ( line_nr=0; line_nr<sizeof(lines); line_nr++ ) {
    sscanf( lines[line_nr], "Version:%*[ \t]%s%*[ \t]", suse_version );
    if ( stringp(suse_version) && sizeof(suse_version) != 0 )
      break;
  }
  if ( !stringp(suse_version) || sizeof(suse_version) == 0 )
    werror( "* Warning: Could not find old version number in "
            + suse_spec + " !\n" );
  else {
    lines[line_nr] = "Version: " + new_version;
    Stdio.write_file( suse_spec, (lines * "\n")+"\n" );
  }

  // update changelogs:
  int time = time();
  // debian changelogs:
  string new_log = "steam (" + new_version + ") unstable; urgency=low\n";
  foreach ( changelog, string entry )
    new_log += wrap_string( entry, 78, "  *" ) + "\n";
  new_log += "\n -- " + author + "  " + Calendar.Second( time )->format_smtp()
    + "\n\n";
  foreach ( debian_changelogs, string file ) {
    write( "Updating " + file + " ...\n" );
    mixed err = catch {
      string old_log = Stdio.read_file( file );
      Stdio.write_file( file, new_log + old_log );
    };
    if ( err )
      werror( "* Warning: Could not update changelog " + file + " !\n" );
  }
  // other changelogs:
  new_log = new_version + "\n";
  foreach ( changelog, string entry )
    new_log += wrap_string( entry, 78, "*" ) + "\n";
  new_log += "\n";
  foreach ( other_changelogs, string file ) {
    write( "Updating " + file + " ...\n" );
    mixed err = catch {
      string old_log = Stdio.read_file( file );
      Stdio.write_file( file, new_log + old_log );
    };
    if ( err )
      werror( "* Warning: Could not update changelog " + file + " !\n" );
  }

  string cvs_version = replace( new_version, ".", "_" );
  write( "\nRemember to tag the new version in CVS after committing it:\n"
         + "cvs commit -m steam-" + cvs_version + " ; cvs tag steam-"
         + cvs_version + "\n" );

  return 0;
}
