#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

int test(object me,object _Server,object...args)
{
	int pass = 0;
	_Server->get_factory("User")->execute((["name":"testUser1","pw":"password1"]));
	_Server->get_factory("User")->execute((["name":"testUser2","pw":"password2"]));
	object user1 = _Server->get_module("users")->get_user("testUser1");
	object user2 = _Server->get_module("users")->get_user("testUser2");
	user1->activate_user();
	user2->activate_user();
	args[0]->login("testUser1","password1",1);
	_Server->get_factory("Container")->execute((["name":"testCont"]))->move(OBJ("/home/testUser1"));
	args[0]->login("testUser2","password2",1);
	write("Trying to access container created by user1 as user2: ");
	mixed result = catch{OBJ("/home/testUser1/testCont")->delete();};
	if(result!=0){
		pass=1;
		write("passed\n");
	}
	else write("failed\n");
	args[0]->login("root","steam",1);
	user1->delete();
	user2->delete();
	return pass;
}
