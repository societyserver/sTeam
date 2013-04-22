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
 * $Id: cert.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: cert.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

import Standards.ASN1.Types;

#if !constant(PrintableString) 
class PrintableString {
    inherit asn1_printable_string;
}
#endif


/**
 * Read a certificate file 'path' which has to be encoded
 * appropriately (base64).
 *  
 * @param path - the path of the filename, or an array of paths or
 *               arrays ({ cert-path, key-path })
 * @return mapping of certificate components
 */
mapping read_certificate(string|array path)
{
    array cert_files = ({ });
    if ( stringp(path) ) cert_files = ({ path });
    else if ( arrayp(path) ) {
      foreach ( path, mixed path_elem )
        cert_files += ({ path_elem });
    }
    mapping result = ([ ]);

    foreach ( cert_files, mixed files ) {
      if ( stringp(files) ) result = try_read_certificate( files );
      else if ( arrayp(files) && sizeof(files)>1 )
        result = try_read_certificate( files[0], files[1] );
      else if ( arrayp(files) )
        result = try_read_certificate( files[0] );
      else continue;
      if ( !mappingp(result) ) continue;
      if ( result->cert && result->rsa && result->random )
        break;
    }
    
    if ( result->cert == 0 ) 
      error(sprintf("Failed to read certificate from file %O\n", path));
    if ( result->rsa == 0 )
      error(sprintf("Failed to read RSA private key for certificate from file %O\n", path));

    return result;
}

static mapping try_read_certificate ( string cert_file, void|string key_file )
{
  mapping result = ([ ]);
  string f = Stdio.read_file( cert_file );
  if ( !stringp(f) ) return UNDEFINED;
  object msg = Tools.PEM.pem_msg()->init(f);
  if ( !objectp(msg) ) return UNDEFINED;
  object part = msg->parts["CERTIFICATE"] || msg->parts["X509 CERTIFICATE"];
  if ( !objectp(part) ) return UNDEFINED;
  result->cert = part->decoded_body();
  
  part = msg->parts["RSA PRIVATE KEY"];
  if ( !objectp(part) ) {
    if ( !stringp(key_file) ) return result;
    f = Stdio.read_file( key_file );
    if ( !stringp(f) ) return result;
    msg = Tools.PEM.pem_msg()->init(f);
    if ( !objectp(msg) ) return result;
    part = msg->parts["RSA PRIVATE KEY"];
  }
  if ( !objectp(part) ) return result;
  string key = part->decoded_body();
  result->key = key;
  result->rsa = Standards.PKCS.RSA.parse_private_key( key );

#if constant(Crypto.Random)
  result->random = Crypto.Random.random_string;
#else    
  result->random = Crypto.randomness.reasonably_random()->read;
#endif

  return result;
}


string create_cert(mapping vars)
{
#if constant(Crypto.Random)
    function random = Crypto.Random.random_string;
#else    
    function random = Crypto.randomness.reasonably_random()->read;
#endif

#if constant(Crypto.RSA) 
    object rsa = Crypto.RSA()->generate_key(512, random);
#else
    object rsa = Crypto.rsa()->generate_key(512, random);
#endif

    array attr = ({ });
    attr += 
	({ ([ "countryName": PrintableString(vars->country),
	    "organizationName": PrintableString(vars->organization),
	    "organizationUnitName": PrintableString(vars->unit),
	    "localityName": PrintableString(vars->locality),
	    "stateOrProvinceName":PrintableString(vars->province),
	    "commonName": PrintableString(vars->name), ]),
	       });
    string cert = Tools.X509.make_selfsigned_rsa_certificate(
	rsa, 60*60*24*1000, attr);
    string der = MIME.encode_base64(cert);
    string rsa_str = MIME.encode_base64(Standards.PKCS.RSA.private_key(rsa));
    
    der = "-----BEGIN CERTIFICATE-----\n"+der+
	"\n-----END CERTIFICATE-----\n";
    der += "\n-----BEGIN RSA PRIVATE KEY-----\n"+
	rsa_str+"\n-----END RSA PRIVATE KEY\n";
    return der;
}
