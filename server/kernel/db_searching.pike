inherit "/kernel/module";
function fDb;

static final void load_module()
{
    load_db_mapping();
}

static final void load_db_mapping()
{
    string sDbTable;
    //    werror("***");
    [fDb, sDbTable] = _Database->connect_db_mapping();
    //    werror(" *** handle received is %O\n", fDb);
}

array(mapping(string:mixed)) query(object|string q, mixed ... extraargs)
{
    return fDb()->query(q, @extraargs);
}

int|object big_query(string q, mixed ... bindings)
{
    return fDb()->big_query(q, @bindings);
}

array(string) list_tables(string|void wild)
{
    return fDb()->list_tables(wild);
}
