#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

// Generalized test case to move an object to a non exestential location
int testcase(object me,object _Server,object x)
{
	int pass = 0;
	mixed result = catch{x->move(OBJ("non-existential-path"));};
	if(result!=0)pass=1;
	return pass;
}
