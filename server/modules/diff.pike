inherit "/kernel/module";

#include <attributes.h>

string diff_html(object oldObject, object newObject)
{
    if ( !objectp(oldObject) || !objectp(newObject) )
	return "";
    array diff = low_diff(oldObject, newObject);
    array newTokens, oldTokens;

    newTokens = diff[0];
    oldTokens = diff[1];

    string resultStr = "";
    int i, j, szo, szn;
    i = j = 0;
    szo = sizeof(oldTokens);
    szn = sizeof(newTokens);
    if ( szn > szo )
	oldTokens += allocate(szn-szo);
    else if ( szo > szn )
	newTokens += allocate(szo-szn);

    int line1, line2;
    line1 = line2 = 1;
    while ( i < szn && j < szo )
    {
	if ( newTokens[i] == oldTokens[j] ) {
	    line1 += sizeof(newTokens[i]);
	    line2 += sizeof(oldTokens[j]);
	    i++;
	    j++;
	}
	else {
	    if ( !arrayp(newTokens[i]) || sizeof(newTokens[i])  == 0 ) {
		resultStr += "#" + line2 + ": <br />";
		resultStr += "-" + (oldTokens[j]*"<br />") + "<br />";
		line2 += sizeof(oldTokens[j]);
	    }
	    else if ( !arrayp(oldTokens[j]) || sizeof(oldTokens[j]) == 0 ) {
		resultStr += "#" + line1 + ": <br />";
		resultStr += "+" + (newTokens[j]*"<br />") + "<br />";
		line1 += sizeof(newTokens[i]);
	    }
	    else {
		resultStr += "#" + line1 + ": <br />";
		resultStr += "+" + (newTokens[j]*"<br />") + "<br />";
		resultStr += "-" + (oldTokens[j]*"<br />") + "<br />";
		line1 += sizeof(newTokens[i]);
		line2 += sizeof(oldTokens[j]);
	    }
	    i++;
	    j++;
	}
    }
    if ( !xml.utf8_check(resultStr) )
	resultStr = string_to_utf8(resultStr);
    return resultStr;
}

string lines(string l)
{
    return "<line><![CDATA[" + l + "]]></line>";
}

string map_lines(array a)
{
    return map(a, lines) * "\n";
}

string diff_latest_xml(object obj) {
  if (!objectp(obj)) return "<!-- obj is no object -->";
  object latest = obj->query_attribute(DOC_VERSIONS)[obj->query_attribute(DOC_VERSION)-1];
  if (!objectp(latest)) return "<!-- dont found latest version, maybe no existing versions ? -->";

  return diff_xml(latest, obj, 0);
}

string diff_xml(object|string oldObject, object|string newObject, void|int with_xml_header)
{
    if ( stringp(oldObject) )
	oldObject = find_object((int)oldObject);
    if ( stringp(newObject) ) 
	newObject = find_object((int)newObject);
    
    if ( !objectp(oldObject) || !objectp(newObject) ) 
	return 0;

    array diff = low_diff(oldObject, newObject);
    array newTokens, oldTokens;

    newTokens = diff[0];
    oldTokens = diff[1];

    string resultStr = "";
    if ( !zero_type(with_xml_header) && with_xml_header !=0 )
	resultStr += "<?xml version=\"1.0\" ?>\n";

    resultStr += sprintf( "<diff source1=\"%d\" source2=\"%d\">\n", oldObject->get_object_id(), newObject->get_object_id() );
    int i, j, szo, szn;
    i = j = 0;
    szo = sizeof(oldTokens);
    szn = sizeof(newTokens);

    if ( szn > szo )
	oldTokens += allocate(szn-szo);
    else if ( szo > szn )
	newTokens += allocate(szo-szn);

    int line1, line2;
    line1 = line2 = 1;
    while ( i < szn && j < szo )
    {
	if ( newTokens[i] == oldTokens[j] ) {
	    line1 += sizeof(newTokens[i]);
	    line2 += sizeof(oldTokens[j]);
	    i++;
	    j++;
	}
	else {
	    if ( !arrayp(newTokens[i]) || sizeof(newTokens[i])  == 0 ) {
		resultStr += sprintf( "<change line1=\"%d\" line2=\"%d\">\n", line1, line2 );
		resultStr += "<deleted>" + map_lines(oldTokens[j]) + "</deleted>\n";
		resultStr += "</change>\n";
		line2 += sizeof(oldTokens[j]);
	    }
	    else if ( !arrayp(oldTokens[j]) || sizeof(oldTokens[j]) == 0 ) {
		resultStr += sprintf( "<change line1=\"%d\" line2=\"%d\">\n", line1, line2 );
		resultStr += "<added>" + map_lines(newTokens[i]) + "</added>\n";
		resultStr += "</change>\n";
		line1 += sizeof(newTokens[i]);
	    }
	    else {
		resultStr += sprintf( "<change line1=\"%d\" line2=\"%d\">\n", line1, line2 );
		resultStr += "<added>" + map_lines(newTokens[i]) + "</added>\n";
		resultStr += "<deleted>" + map_lines(oldTokens[j]) + "</deleted>\n";
		resultStr += "</change>\n";
		line1 += sizeof(newTokens[i]);
		line2 += sizeof(oldTokens[j]);
	    }
	    i++;
	    j++;
	}
    }
    string newcontent = "";
    newcontent = replace(newObject->get_content(), "\r", "");
    array lines = newcontent / "\n";
    resultStr += "<content>" + map_lines(lines) + "</content>";
    resultStr += "</diff>";
    if ( !xml.utf8_check(resultStr) )
	resultStr = string_to_utf8(resultStr);
    return resultStr;
}


array low_diff(object oldObject, object newObject)
{
    if ( !objectp( oldObject ) )
	return 0;
    if ( !objectp( newObject ) )
	return 0;

    string oldcontent, newcontent;
    oldcontent = oldObject->get_content();
    oldcontent = replace(oldcontent, "\r", "");
    newcontent = newObject->get_content();
    newcontent = replace(newcontent, "\r", "");

    array newArr = newcontent / "\n";
    array oldArr = oldcontent / "\n";
    
#if 0
    int newsize = sizeof(newArr);
    int oldsize = sizeof(oldArr);
    if ( newsize > oldsize )
	oldArr += allocate(newsize - oldsize);
    else if ( oldsize > newsize )
	newArr += allocate(oldsize - newsize);
    for ( int x = 0; x < max(newsize,oldsize); x++ )
	if ( !stringp(oldArr[x]) )
	    oldArr[x] = "";
	else if ( !stringp(newArr[x]) )
	    newArr[x] = "";
#endif
    array diff = Array.diff(newArr, oldArr);
    return diff;
}

string get_identifier() { return "diff"; }
