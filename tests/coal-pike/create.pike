#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase1(object me,object _Server)
{
	int pass = 0;
	write ("creating a new Calendar\n");
	int result =_Server->get_factory("Calendar")->execute((["name":"TestCalendar"]))->move(OBJ(me->get_last_trail()->query_attribute("OBJ_PATH"))); 
	if(result == 1) pass = 1;
//	if(pass == 1)
//		OBJ(me->get_last_trail()->query_attribute("OBJ_PATH")+"/TestCalendar")->delete();
	return pass;
}

int testcase2(object me,object _Server)
{
	int pass = 0;
	write("creating a new Container\n");
	int result =_Server->get_factory("Container")->execute((["name":"TestContainer"]))->move(OBJ(me->get_last_trail()->query_attribute("OBJ_PATH"))); 
	if(result == 1) pass = 1;
//	if(pass == 1)
//		OBJ(me->get_last_trail()->query_attribute("OBJ_PATH")+"/TestContainer")->delete();
	return pass;

}

int testcase3(object me,object _Server)
{
	int pass = 0;
	write("creating a new Date\n");
	int result =_Server->get_factory("Date")->execute((["name":"TestDate"]))->move(OBJ(me->get_last_trail()->query_attribute("OBJ_PATH"))); 
	if(result == 1) pass = 1;
//	if(pass == 1)
//		OBJ(me->get_last_trail()->query_attribute("OBJ_PATH")+"/TestDate")->delete();
	return pass;

}

int testcase4(object me,object _Server)
{
	int pass = 0;
	write("creating a new Document\n");
	int result =_Server->get_factory("Document")->execute((["name":"TestDocument"]))->move(OBJ(me->get_last_trail()->query_attribute("OBJ_PATH"))); 
	if(result == 1) pass = 1;
//	if(pass == 1)
//		OBJ(me->get_last_trail()->query_attribute("OBJ_PATH")+"/TestDocument")->delete();
	return pass;

}
