#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	int pass = 0;
	_Server->get_factory("Room")->execute((["name":"TestsubRoom"]))->move(OBJ("/TestRoom"));
	mixed result = catch{me->move(OBJ("/TestRoom/TestsubRoom"));};
	write("Moving user\n");
	if(result == 0)pass=1;
	me->move(OBJ("/TestRoom"));
	OBJ("/TestRoom/TestsubRoom")->delete();
	return pass;
}

int testcase2(object me,object _Server)
{
	int pass = 0;
	mixed result = catch{me->move(OBJ("nopath"));};
	write("Moving to a non existential location nopath.\n");
	if(result !=0)pass=1;
	me->move(OBJ("/TestRoom")); 
	return pass;
}

int testcase3(object me,object _Server)
{
	int pass = 0;
	mixed result = 0;
	int res =_Server->get_factory("Container")->execute((["name":"Testmove3"]))->move(OBJ("/TestRoom"));
	result = catch{me->move(OBJ("/TestRoom/Testmove3"));};
	write("Moving user into a container\n");
	if(result != 0)pass=1;
	OBJ("/TestRoom/Testmove3")->delete();
	return pass;	
}

int testcase4(object me,object _Server)
{
	int pass = 0;
	_Server->get_factory("Room")->execute((["name":"Testmove4"]))->move(OBJ("/TestRoom"));
	_Server->get_factory("Container")->execute((["name":"Testcontmove4"]))->move(OBJ("/TestRoom"));
	object room = OBJ("/TestRoom/Testmove4");
	object container = OBJ("/TestRoom/Testcontmove4");
	mixed result = catch{room->move(container);};
	write("Moving room inside container\n");
	if(result!=0)pass=1;
	room->delete();
	container->delete();
	return pass;
}
