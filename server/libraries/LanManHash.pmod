/*
 * Simple DES hash algorithm to create (weak) LanManager passwords
 *
 * Interface:
 *   string lanman_hash ( string password )
 *
 * Adapted to pike from C code. The original source code is the file
 * smbdes.c from the following package:
 *   http://www.nomis52.net/data/mkntpwd.tar.gz
 *
 * The original author is: Andrew Tridgell
 * The code was adapted from C to pike by: exodus@uni-paderborn.de
 *
 * The original file header follows (this file is under the same
 * license [GNU General Public License]):
 * --------------------------------------------------------------------

   Unix SMB/Netbios implementation.
   Version 1.9.

   a partial implementation of DES designed for use in the
   SMB authentication protocol

   Copyright (C) Andrew Tridgell 1997

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 * --------------------------------------------------------------------

   NOTES:

   This code makes no attempt to be fast! In fact, it is a very
   slow implementation

   This code is NOT a complete DES implementation. It implements only
   the minimum necessary for SMB authentication, as used by all SMB
   products (including every copy of Microsoft Windows95 ever sold)

   In particular, it can only do a unchained forward DES pass. This
   means it is not possible to use this code for encryption/decryption
   of data, instead it is only useful as a "hash" algorithm.

   There is no entry point into this code that allows normal DES operation.

   I believe this means that this code does not come under ITAR
   regulations but this is NOT a legal opinion. If you are concerned
   about the applicability of ITAR regulations to this code then you
   should confirm it for yourself (and maybe let me know if you come
   up with a different answer to the one above)

 * --------------------------------------------------------------------
 */

static array perm1 = ({ 57, 49, 41, 33, 25, 17,  9,
                         1, 58, 50, 42, 34, 26, 18,
                        10,  2, 59, 51, 43, 35, 27,
                        19, 11,  3, 60, 52, 44, 36,
                        63, 55, 47, 39, 31, 23, 15,
                         7, 62, 54, 46, 38, 30, 22,
                        14,  6, 61, 53, 45, 37, 29,
                        21, 13,  5, 28, 20, 12,  4 });

static array perm2 = ({ 14, 17, 11, 24,  1,  5,
                         3, 28, 15,  6, 21, 10,
                        23, 19, 12,  4, 26,  8,
                        16,  7, 27, 20, 13,  2,
                        41, 52, 31, 37, 47, 55,
                        30, 40, 51, 45, 33, 48,
                        44, 49, 39, 56, 34, 53,
                        46, 42, 50, 36, 29, 32 });

static array perm3 = ({ 58, 50, 42, 34, 26, 18, 10,  2,
                        60, 52, 44, 36, 28, 20, 12,  4,
                        62, 54, 46, 38, 30, 22, 14,  6,
                        64, 56, 48, 40, 32, 24, 16,  8,
                        57, 49, 41, 33, 25, 17,  9,  1,
                        59, 51, 43, 35, 27, 19, 11,  3,
                        61, 53, 45, 37, 29, 21, 13,  5,
                        63, 55, 47, 39, 31, 23, 15,  7 });

static array perm4 = ({ 32,  1,  2,  3,  4,  5,
                         4,  5,  6,  7,  8,  9,
                         8,  9, 10, 11, 12, 13,
                        12, 13, 14, 15, 16, 17,
                        16, 17, 18, 19, 20, 21,
                        20, 21, 22, 23, 24, 25,
                        24, 25, 26, 27, 28, 29,
                        28, 29, 30, 31, 32,  1 });

static array perm5 = ({ 16,  7, 20, 21,
                        29, 12, 28, 17,
                         1, 15, 23, 26,
                         5, 18, 31, 10,
                         2,  8, 24, 14,
                        32, 27,  3,  9,
                        19, 13, 30,  6,
                        22, 11,  4, 25});


static array perm6 = ({ 40,  8, 48, 16, 56, 24, 64, 32,
                        39,  7, 47, 15, 55, 23, 63, 31,
                        38,  6, 46, 14, 54, 22, 62, 30,
                        37,  5, 45, 13, 53, 21, 61, 29,
                        36,  4, 44, 12, 52, 20, 60, 28,
                        35,  3, 43, 11, 51, 19, 59, 27,
                        34,  2, 42, 10, 50, 18, 58, 26,
                        33,  1, 41,  9, 49, 17, 57, 25 });


static array sc = ({ 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 });

static array sbox = ({
        ({ ({14,  4, 13,  1,  2, 15, 11,  8,  3, 10,  6, 12,  5,  9,  0,  7}),
         ({0, 15,  7,  4, 14,  2, 13,  1, 10,  6, 12, 11,  9,  5,  3,  8}),
         ({4,  1, 14,  8, 13,  6,  2, 11, 15, 12,  9,  7,  3, 10,  5,  0}),
         ({15, 12,  8,  2,  4,  9,  1,  7,  5, 11,  3, 14, 10,  0,  6, 13}) }),

        ({ ({15,  1,  8, 14,  6, 11,  3,  4,  9,  7,  2, 13, 12,  0,  5, 10}),
         ({3, 13,  4,  7, 15,  2,  8, 14, 12,  0,  1, 10,  6,  9, 11,  5}),
         ({0, 14,  7, 11, 10,  4, 13,  1,  5,  8, 12,  6,  9,  3,  2, 15}),
         ({13,  8, 10,  1,  3, 15,  4,  2, 11,  6,  7, 12,  0,  5, 14,  9}) }),

        ({ ({10,  0,  9, 14,  6,  3, 15,  5,  1, 13, 12,  7, 11,  4,  2,  8}),
         ({13,  7,  0,  9,  3,  4,  6, 10,  2,  8,  5, 14, 12, 11, 15,  1}),
         ({13,  6,  4,  9,  8, 15,  3,  0, 11,  1,  2, 12,  5, 10, 14,  7}),
         ({1, 10, 13,  0,  6,  9,  8,  7,  4, 15, 14,  3, 11,  5,  2, 12}) }),

        ({ ({7, 13, 14,  3,  0,  6,  9, 10,  1,  2,  8,  5, 11, 12,  4, 15}),
         ({13,  8, 11,  5,  6, 15,  0,  3,  4,  7,  2, 12,  1, 10, 14,  9}),
         ({10,  6,  9,  0, 12, 11,  7, 13, 15,  1,  3, 14,  5,  2,  8,  4}),
         ({3, 15,  0,  6, 10,  1, 13,  8,  9,  4,  5, 11, 12,  7,  2, 14}) }),

        ({ ({2, 12,  4,  1,  7, 10, 11,  6,  8,  5,  3, 15, 13,  0, 14,  9}),
         ({14, 11,  2, 12,  4,  7, 13,  1,  5,  0, 15, 10,  3,  9,  8,  6}),
         ({4,  2,  1, 11, 10, 13,  7,  8, 15,  9, 12,  5,  6,  3,  0, 14}),
         ({11,  8, 12,  7,  1, 14,  2, 13,  6, 15,  0,  9, 10,  4,  5,  3}) }),

        ({ ({12,  1, 10, 15,  9,  2,  6,  8,  0, 13,  3,  4, 14,  7,  5, 11}),
         ({10, 15,  4,  2,  7, 12,  9,  5,  6,  1, 13, 14,  0, 11,  3,  8}),
         ({9, 14, 15,  5,  2,  8, 12,  3,  7,  0,  4, 10,  1, 13, 11,  6}),
         ({4,  3,  2, 12,  9,  5, 15, 10, 11, 14,  1,  7,  6,  0,  8, 13}) }),

        ({ ({4, 11,  2, 14, 15,  0,  8, 13,  3, 12,  9,  7,  5, 10,  6,  1}),
         ({13,  0, 11,  7,  4,  9,  1, 10, 14,  3,  5, 12,  2, 15,  8,  6}),
         ({1,  4, 11, 13, 12,  3,  7, 14, 10, 15,  6,  8,  0,  5,  9,  2}),
         ({6, 11, 13,  8,  1,  4, 10,  7,  9,  5,  0, 15, 14,  2,  3, 12}) }),

        ({ ({13,  2,  8,  4,  6, 15, 11,  1, 10,  9,  3, 14,  5,  0, 12,  7}),
         ({1, 15, 13,  8, 10,  3,  7,  4, 12,  5,  6, 11,  0, 14,  9,  2}),
         ({7, 11,  4,  1,  9, 12, 14,  2,  0,  6, 10, 13, 15,  3,  5,  8}),
         ({2,  1, 14,  7,  4, 10,  8, 13, 15, 12,  9,  0,  3,  5,  6, 11}) })
});

static string make_string ( int size ) {
  string out = "";
  for ( int i=0; i<size; i++ ) out += " ";
  return out;
}

static string permute ( string in, array(int) p, int n)
{
  string out = make_string(n);
  for (int i=0;i<n;i++)
    out[i] = in[p[i]-1];
  return out;
}

static string lshift(string d, int count, int n)
{
  string out = make_string(64);
  for ( int i=0; i<n; i++ ) out[i] = d[(i+count)%n];
  return out;
}

static string concat ( string in1, string in2, int l1, int l2 )
{
  string out = make_string( l1 + l2 );
  for ( int i=0; i<l1; i++ ) out[i] = in1[i];
  for ( int i=0; i<l2; i++ ) out[l1+i] = in2[i];
  return out;
}

static string xor(string in1, string in2, int n)
{
  string out = make_string(n);
        for (int i=0;i<n;i++)
                out[i] = in1[i] ^ in2[i];
  return out;
}

static string dohash(string in, string key)
{
  string out = make_string(64);
        int i, j, k;
  string pk1 = make_string(56);
  string c = make_string(28);
  string d = make_string(28);
  string cd = make_string(56);
  array ki = ({ }); 
  for ( int z=0; z<16; z++ ) ki += ({ make_string(48) });
  string pd1 = make_string(64);
  string l = make_string(32), r = make_string(32);
  string rl = make_string(64);

        pk1 = permute( key, perm1, 56);

        for (i=0;i<28;i++)
                c[i] = pk1[i];
        for (i=0;i<28;i++)
                d[i] = pk1[i+28];

        for (i=0;i<16;i++) {
                c = lshift(c, sc[i], 28);
                d = lshift(d, sc[i], 28);

                cd = concat( c, d, 28, 28);
                ki[i] = permute( cd, perm2, 48);
        }

        pd1 = permute( in, perm3, 64);

        for (j=0;j<32;j++) {
                l[j] = pd1[j];
                r[j] = pd1[j+32];
        }

        for (i=0;i<16;i++) {
    string er = make_string(48);
    string erk = make_string(48);
    array b = ({ });
    for ( int z=0; z<8; z++ ) {
      b += ({ make_string(6) });
    }
    string cb = make_string(32);
    string pcb = make_string(32);
    string r2 = make_string(32);

                er = permute( r, perm4, 48);

                erk = xor( er, ki[i], 48);

                for (j=0;j<8;j++)
                        for (k=0;k<6;k++)
                                b[j][k] = erk[j*6 + k];

                for (j=0;j<8;j++) {
                        int m, n;
                        m = (b[j][0]<<1) | b[j][5];

                        n = (b[j][1]<<3) | (b[j][2]<<2) | (b[j][3]<<1) | b[j][4];

                        for (k=0;k<4;k++)
                                b[j][k] = (sbox[j][m][n] & (1<<(3-k)))?1:0;
                }

                for (j=0;j<8;j++)
                        for (k=0;k<4;k++)
                                cb[j*4+k] = b[j][k];
                pcb = permute( cb, perm5, 32);

                r2 = xor( l, pcb, 32);

                for (j=0;j<32;j++)
                        l[j] = r[j];

                for (j=0;j<32;j++)
                        r[j] = r2[j];
        }

        rl = concat( r, l, 32, 32);

        out = permute( rl, perm6, 64);
  return out;
}

static string str_to_key(string str)
{
  string key = "12345678";
        int i;

        key[0] = str[0]>>1;
        key[1] = ((str[0]&0x01)<<6) | (str[1]>>2);
        key[2] = ((str[1]&0x03)<<5) | (str[2]>>3);
        key[3] = ((str[2]&0x07)<<4) | (str[3]>>4);
        key[4] = ((str[3]&0x0F)<<3) | (str[4]>>5);
        key[5] = ((str[4]&0x1F)<<2) | (str[5]>>6);
        key[6] = ((str[5]&0x3F)<<1) | (str[6]>>7);
        key[7] = str[6]&0x7F;
        for (i=0;i<8;i++) {
                key[i] = (key[i]<<1);
        }
  return key;
}

static string smbhash( string in, string key)
{
  string out = make_string(8);
  string outb = make_string(64);
  string inb = make_string(64);
  string keyb = make_string(64);
  string key2 = make_string(8);
        int i;

        key2 = str_to_key(key);

        for (i=0;i<64;i++) {
                inb[i] = (in[i/8] & (1<<(7-(i%8)))) ? 1 : 0;
                keyb[i] = (key2[i/8] & (1<<(7-(i%8)))) ? 1 : 0;
                outb[i] = 0;
        }

        outb = dohash( inb, keyb);

        for (i=0;i<8;i++) {
                out[i] = 0;
        }

        for (i=0;i<64;i++) {
                if (outb[i])
                        out[i/8] |= (1<<(7-(i%8)));
        }
  return out;
}

static string string_to_hex ( string str ) {
  string out = "";
  for ( int i=0; i<sizeof(str); i++ )
    out += sprintf( "%02x", str[i] );
  return out;
}

string lanman_hash ( string password ) {
  if ( !stringp( password ) ) return 0;
  string pw = upper_case( password );
  if ( sizeof( pw ) > 14 ) pw = pw[0..13];
  else while ( sizeof( pw ) < 14 ) pw += "\0";

  string out = "";
  array tmp = ({ 0x4b, 0x47, 0x53, 0x21, 0x40, 0x23, 0x24, 0x25 });
  string sp8 = "12345678";
  for ( int i=0; i<8; i++ ) sp8[i] = tmp[i];
  out += smbhash( sp8, pw[0..6] );
  out += smbhash( sp8, pw[7..13] );
  return upper_case( string_to_hex( out ) );
}

