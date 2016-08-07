#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int testcase(object me,object _Server,string type)
{
	int pass = 0;
	object room = OBJ("/TestRoom");
	mixed result =catch{ _Server->get_factory(type)->execute((["name":"TestObj"+type]))->move(room); };
	if(result ==0)pass=1;
	object ref = OBJ("/TestRoom/TestObj");
	if(ref!=0)ref->delete();
	return pass;

}
