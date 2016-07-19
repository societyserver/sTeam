#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	object code = ((program)"create_object.pike")();
	array(function) foo = values(code);
	int success = 1;
	array(string) testClass = ({"Container","Document","Room","Exit","User","Group"});
	for(int i =0;i<sizeof(testClass);i++){
		write("Creating a "+testClass[i]+": ");	
		int ctr = foo[0](me,_Server,testClass[i]);
		if(ctr == 0)success=0;
		if(ctr==1)write("passed\n");
		else write("failed\n");
	}
	return success;
}

int testcase2(object me,object _Server)
{
	int pass=0;
	write("Creating a class that does not exists\n");
	mixed result = _Server->get_factory("NoClass");
	if(result == 0) pass =1;
	return pass;
}


