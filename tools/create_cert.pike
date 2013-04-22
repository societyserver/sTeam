#!/usr/local/bin/pike
/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: create_cert.pike.in,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: create_cert.pike.in,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

import Standards.ASN1.Types;


#if !constant(PrintableString) 
class PrintableString {
    inherit asn1_printable_string;
}
#endif

void main(int argc, array argv)
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
    string fname = "steam.cer";
    int j;
    for ( j = 1; j < argc; j++ ) {
      if ( sscanf(argv[j], "--file=%s", fname) == 0 )
	break;
    }

    if ( j == argc ) {
      string hname = gethostname();
	attr += 
	({ ([ "countryName": PrintableString("Germany"),
	    "organizationName": PrintableString("Uni Paderborn"),
	    "organizationUnitName": PrintableString("sTeam"),
	    "localityName": PrintableString("Paderborn"),
	    "stateOrProvinceName":PrintableString("NRW"),
	    "commonName": PrintableString(hname), ]),
	});
    }
    for ( int i = j; i < argc; i++ ) {
      attr += 
	({ ([ "countryName": PrintableString("Germany"),
	    "organizationName": PrintableString("Uni Paderborn"),
	    "organizationUnitName": PrintableString("sTeam"),
	    "localityName": PrintableString("Paderborn"),
	    "stateOrProvinceName":PrintableString("NRW"),
	    "commonName": PrintableString(argv[i]), ]),
	       });
    }		
    string cert = Tools.X509.make_selfsigned_rsa_certificate(
	rsa, 60*60*24*1000, attr);
    string der = MIME.encode_base64(cert);
    string rsa_str = MIME.encode_base64(Standards.PKCS.RSA.private_key(rsa));
    
    der = "-----BEGIN CERTIFICATE-----\n"+der+
	"\n-----END CERTIFICATE-----\n";
    Stdio.write_file(fname, der+
		     "\n-----BEGIN RSA PRIVATE KEY-----\n"+
		     rsa_str+"\n-----END RSA PRIVATE KEY\n");
}
