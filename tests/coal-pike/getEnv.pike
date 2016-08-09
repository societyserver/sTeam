#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int callingFunction(object me,object _Server,object...args)
{
	object parent = OBJ("/TestRoom");
	_Server->get_factory("Room")->execute((["name":"getEnv"]))->move(parent);
	object obj = OBJ("/TestRoom/getEnv");
	int pass = 0;
	write("Calling get_environment: ");
	if(parent==obj->get_environment()) pass=1;
	if(pass == 1) write("passed\n");
	else write("failed\n");	
	return pass;
}
