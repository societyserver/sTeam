#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	int pass = 0;
	write ("creating a new Calendar\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Calendar")->execute((["name":"TestCalendar"]))->move(room); 
	if(result == 1) pass = 1;
	if(pass == 1)
		OBJ("TestRoom/TestCalendar")->query_attribute("OBJ_NAME");
	return pass;
}

int testcase2(object me,object _Server)
{
	int pass = 0;
	write("creating a new Container\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Container")->execute((["name":"TestContainer"]))->move(room); 
	if(result == 1) pass = 1;
	if(pass == 1)
		OBJ("TestRoom/TestContainer")->query_attribute("OBJ_NAME");
	return pass;

}

int testcase3(object me,object _Server)
{
	int pass = 0;
	write("creating a new Date\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Date")->execute((["name":"TestDate"]))->move(room); 
	if(result == 1) pass = 1;
	if(pass == 1)
		OBJ("TestRoom/TestDate")->query_attribute("OBJ_NAME");
	return pass;

}

int testcase4(object me,object _Server)
{
	int pass = 0;
	write("creating a new Document\n");
	object room = OBJ("/TestRoom");
	int result =_Server->get_factory("Document")->execute((["name":"TestDocument"]))->move(room); 
	if(result == 1) pass = 1;
	if(pass == 1)
		OBJ("TestRoom/TestDocument")->query_attribute("OBJ_NAME");
	return pass;

}

int testcase5(object me,object _Server)
{
	int pass=0;
	write("Creating a class that does not exists\n");
	mixed result = _Server->get_factory("NoClass");
	if(result == 0) pass =1;
	return pass;
}

