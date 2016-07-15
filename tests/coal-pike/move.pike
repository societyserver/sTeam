#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	int pass = 0;
	me->move(OBJ("/home/root"));
	string oldpath = me->get_last_trail()->query_attribute("OBJ_PATH");
	write("Current location of user: "+oldpath+"\n");
	me->move(OBJ("/new1"));
	write("Moving user to /new1\n");
	string newpath = me->get_last_trail()->query_attribute("OBJ_PATH");
	write("New location of user: "+newpath+"\n");
	if(newpath=="/new1" && oldpath=="/home/root")pass=1;
	string result = (pass==1)?"passed\n":"fail\n";
	me->move(OBJ("/home/root"));
	return pass;
}

int testcase2(object me,object _Server)
{
	int pass = 0;
	me->move("/home/root");
	string oldpath = me->get_last_trail()->query_attribute("OBJ_PATH");
	write("Current location of user: "+oldpath+"\n");
	mixed result = catch{me->move(OBJ("nopath"));};
	write("Moving to a non existential location nopath.\n");
	if(result ==0)pass=1; 
	return pass;
}
