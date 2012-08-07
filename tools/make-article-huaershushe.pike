inherit "iconv.pike";

/*
mapping fail = ([]);
array res = ({});


object zuixinxiaoxi = OBJ("/home/societyserver.huaershushe/huaershushe/guanyuwomen/zuixinxiaoxi/");
object huodongtongzhi = OBJ("/home/societyserver.huaershushe/huaershushe/zhiyuanzhetuandui/huodongtongzhi/");
object xingdongzuji = OBJ("/home/societyserver.huaershushe/huaershushe/fuwufanwei/xingdongzuji/");
object shuyuan = OBJ("/home/societyserver.huaershushe/huaershushe/fuwufanwei/shuyuan/");
*/

function OBJ;

void create(function _OBJ)
{
    OBJ=_OBJ;
}
//object iconv = (object)"iconv.pike"; 
mixed make_article(int id, object parent, void|string baseurl, void|string type)
{ 
    if (!baseurl)
        baseurl = "http://old.huaershushe.com/files/Article_Detail.asp?id=";
 
    mapping headers = ([ "host":"huaershushe.com"]);
    mapping article = fetch_article(baseurl+(string)id, ([]), headers); 
    write("got article: %O:%O:%O\n", sizeof(article->content), article->charset, article["content-type"]);
    string content = conv(article);
    write("converted\n");

    object new = OBJ("/home/mbaehr/eyevt-structure.pike")->provide_instance()->make_article(content, parent, baseurl+(string)id, article["content-type"], type, "utf-8", 0, ([]), headers); 
    return new; 
}

mapping fetch_article(string url, void|mapping query, void|mapping headers)
{   
    object remote = Protocols.HTTP.get_url(url, query, headers);
    mapping ret =([]);

    ret->content = remote->data();
    ret["content-type"] = remote->headers["content-type"];
    ret->remote = remote;

    Parser.HTML p = Parser.HTML();
    p->add_tag("meta", ({ get_content_type, ret }));
    p->finish(remote->data())->read();
    ret->content=remote->data();
    return ret;
}

void get_content_type(Parser.HTML parser, mapping args, mapping ret)
{   
    werror("FLOWER: get_content_type(%O)\n", args);
    if (args["http-equiv"] != "Content-Type")
        return 0;

    mapping content_type = (mapping)((("content-type="+args->content - " ")/";")[*]/"=");

    foreach (content_type; string key; string value)
    {
        if (!ret[key])
            ret[key] = value;
        else if (arrayp(ret[key]))
            ret[key] += ({ value });
        else
            ret[key] = ({ ret[key], value });
    }
    return 0;
}
