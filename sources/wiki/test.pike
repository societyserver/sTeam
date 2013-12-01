string headingWiki(object obj, object fp, string head)
{
    return "HEADING("+head+")\n";
}

string pikeWiki(object obj, object fp, string pcode) {
    return "PIKE(" + pcode + ")\n";
}

string embedWiki(object obj, object fp, string embed) {
    return "embed(" + embed + ")\n";
}

string annotationWiki(object obj, object fp, string ann) {
    return "annotation(" + ann + "\n";
}

string tagWiki(object obj, object fp, string tagStr) {
    return tagStr + "\n";
}

string linkInternalWiki(object obj, object fp, string link) {
    return "Link(" + link+")\n";
}

string hyperlinkWiki(object obj, object fp, string link) {
    return link + "\n";
}

string barelinkWiki(object obj, object fp, string link) 
{
  return "<a class=\"external\" href=\""+link+"\">"+link+"</a>";
}

string imageWiki(object obj, object fp, string link) {
    return "image(" + link + ")\n";
}

int main()
{
    string wikistr = Stdio.read_file("test.wiki");
    object parser = wiki.Parser(this_object());
    string result = parser->parse(this_object(), this_object(),wikistr);
    write(result);
}
