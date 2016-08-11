#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

//Move the current user to a room
int testcase1(object me,object _Server,object...args)
{
	int pass = 0;
	_Server->get_factory("Room")->execute((["name":"TestsubRoom"]))->move(OBJ("/TestRoom"));
	object obj = OBJ("/TestRoom/TestsubRoom");
	mixed result = catch{me->move(obj);};
	write("Moving user: ");
	if(result == 0)pass=1;
	if(pass==1)write("passed\n");
	else write("failed\n");
	me->move(OBJ("/TestRoom"));
	if(obj!=0)obj->delete();
	return pass;
}

// Generalized test case to move objects to non exestential location
//Currently test Room and User. 
int testcase2(object me,object _Server,object...args)
{
	int pass = 1;
	object code = ((program)"move_nonexistential.pike")();  //imports the file containing the generalized test case
	array(function) foo = values(code);
	_Server->get_factory("Room")->execute((["name":"move2Room"]))->move(OBJ("/TestRoom"));  //Test Room to move
	_Server->get_factory("User")->execute((["name":"move2User","pw":"testpass","email":"abc@example.com"])); //Test User to move
	_Server->get_module("users")->get_user("move2User")->activate_user();
	array(object) testObjects = allocate(2);
//	do{
	testObjects[0]=OBJ("/TestRoom/move2Room");
//	}while(testObjects[0]==0);
//	do{
	testObjects[1]=_Server->get_module("users")->get_user("move2User");
//	}while(testObjects[1]==0);
	int success = 1;
	for(int i = 0;i<sizeof(testObjects);i++){
		write("Moving "+testObjects[i]->get_class()+ " to a non existential path: ");
		int ctr = foo[0](me,_Server,testObjects[i]);
		if(ctr == 0)success =0;
		if(ctr == 1)write("passed\n");
		else write("failed\n");
	}
	
	if(success==0)pass=0;
	if(testObjects[1]!=0)
	testObjects[1]->delete();
	return pass;
}

//Moving user into a container
int testcase3(object me,object _Server,object...args)
{
	int pass = 0;
	mixed result = 0;
	int res =_Server->get_factory("Container")->execute((["name":"Testmove3"]))->move(OBJ("/TestRoom"));
	object obj = OBJ("/TestRoom/Testmove3");
	result = catch{me->move(obj);};
	write("Moving user into a container: ");
	if(result != 0)pass=1;
	if(pass==1)write("passed\n");
	else write("failed\n");
	if(obj!=0)obj->delete();
	return pass;	
}

//Moving a room inside a container
int testcase4(object me,object _Server,object...args)
{
	int pass = 0;
	_Server->get_factory("Room")->execute((["name":"Testmove4"]))->move(OBJ("/TestRoom"));
	_Server->get_factory("Container")->execute((["name":"Testcontmove4"]))->move(OBJ("/TestRoom"));
	object room = OBJ("/TestRoom/Testmove4");
	object container = OBJ("/TestRoom/Testcontmove4");
	mixed result = catch{room->move(container);};
	write("Moving room inside container: ");
	if(result!=0)pass=1;
	if(pass==1)write("passed\n");
	else write("failed\n");
	if(room!=0)
	room->delete();
	if(container!=0)
	container->delete();
	return pass;
}
