#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	object code = ((program)"create_object.pike")();
	array(function) foo = values(code);
	int success = 1;
	array(string) testClass = ({"Container","Document","Room"});
	for(int i =0;i<sizeof(testClass);i++){
		write("Creating a "+testClass[i]+": ");	
		int ctr = foo[0](me,_Server,testClass[i]);
		if(ctr == 0)success=0;
		if(ctr==1)write("passed\n");
		else write("failed");
	}
	return success;
}

/*
int testcase1(object me,object _Server)
{
	int pass = 0;
	write ("creating a new Calendar\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Calendar")->execute((["name":"TestCalendar"]))->move(room); 
	if(result == 1) pass = 1;
	object obj = OBJ("TestRoom/TestCalendar");
	if(obj!=0)
		obj->delete();
	return pass;
}

int testcase2(object me,object _Server)
{
	int pass = 0;
	write("creating a new Container\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Container")->execute((["name":"TestContainer"]))->move(room); 
	object obj = OBJ("TestRoom/TestContainer");
	if(result == 1) pass = 1;
	if(obj != 0)
		obj->delete();
	return pass;

}

int testcase3(object me,object _Server)
{
	int pass = 0;
	write("creating a new Date\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Date")->execute((["name":"TestDate"]))->move(room); 
	if(result == 1) pass = 1;
	object obj = OBJ("TestRoom/TestDate");
	if(obj != 0)
		obj->delete();
	return pass;

}

int testcase4(object me,object _Server)
{
	int pass = 0;
	write("creating a new Document\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Document")->execute((["name":"TestDocument"]))->move(room); 
	object obj = OBJ("TestRoom/TestDocument");
	if(result == 1) pass = 1;
	if(obj != 0)
		obj->delete();
	return pass;

}
*/
int testcase5(object me,object _Server)
{
	int pass=0;
	write("Creating a class that does not exists\n");
	mixed result = _Server->get_factory("NoClass");
	if(result == 0) pass =1;
	return pass;
}

