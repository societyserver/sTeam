#include <attributes.h>

static mapping cache = ([ ]);

mapping lookup_cache(object file)
{
  int last_modified = file->query_attribute(DOC_LAST_MODIFIED);
  mapping data = cache[file];
  if ( mappingp(data) && last_modified > data->cachetime ) {
    m_delete(cache, file);
    return 0;
  }
  return data;
}

static void insert_cache(object file, object xml)
{
  cache[file] = ([ "xml": xml, "cachetime":time() ]);
}

object parse(object xmlfile)
{
  mapping entry = lookup_cache(xmlfile);
  if ( mappingp(entry) )
    return entry->xml;
  object node = xmlDom.parse(xmlfile->get_content());
  insert_cache(xmlfile, node);
  return node;
}

mapping dump() { return cache; }
