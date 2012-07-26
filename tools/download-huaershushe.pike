#!/usr/local/lib/steam/bin/steam

/* 
 * Copyright (C) 2012  Martin Baehr
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
 */

#include "/usr/local/lib/steam/server/include/classes.h"
inherit .client;

#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

object _Server;
object iconv = (object)"iconv.pike";

array docs = ({270,269,266,265,264,263,262,261,259,256,255,251,250,249,247,245,244,242,241,240,239,238,237,235,233,231,230,228,224,223,222,218,216,215,212,211,210,209,208,206,204,199,198,196,195,194,193,185,184,174,173,170,169,166,165,164,163,162,160,154,152,148,147,145,142,141,140,139,138,136,135,132,131,123,120,116,115,112,108,91});

int main(int argc, array(string) argv)
{
    options=init(copy_value(argv));

    options->path = argv[-1];
    _Server=conn->SteamObj(0);

    mapping fail = ([]);
    array res = ({});

    object zuixinxiaoxi = OBJ("/home/societyserver.huaershushe/huaershushe/guanyuwomen/zuixinxiaoxi/");
    object huodongtongzhi = OBJ("/home/societyserver.huaershushe/huaershushe/zhiyuanzhetuandui/huodongtongzhi/");
    object xingdongzuji = OBJ("/home/societyserver.huaershushe/huaershushe/fuwufanwei/xingdongzuji/");



    foreach(docs;; int id) 
    { 
        write("%d\n", id); 
        object new; 
        mixed err = catch{ new = make_article(id, xingdongzuji); }; 
        if (objectp(new))
        { 
            res += ({ new }); 
            docs = docs[1..];
        }
        else
        {
            fail[id]=err; 
            if (!err || arrayp(err) && !sizeof(err))
                 break;
        } 
        write("%d: %O:%O\n", id, new, err); 
    }

    write("loop: %O\n%O\n", fail, res);
    if (sizeof(docs))
        return main(sizeof(argv), argv);
}

mixed make_article(int id, object parent) 
{   
    string baseurl = "http://huaershushe.com/files/Article_Detail.asp?id="; 
 
    mapping article = OBJ("/home/mbaehr/eyevt-structure.pike")->provide_instance()->fetch_article(baseurl+(string)id);
    write("got article: %O:%O:%O\n", sizeof(article->content), article->charset, article["content-type"]);
    string content = iconv->conv(article);
    write("converted\n");

    object|string new = OBJ("/home/mbaehr/eyevt-structure.pike")->provide_instance()->make_article(content, parent, baseurl+(string)id, article["content-type"], "utf-8");
    if (stringp(new))
        throw(new);
    return new;
}

