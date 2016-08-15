#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

// Generalized test case to create various types of objects
int generalCreate(object me,object _Server,object...args)
{
	object code = ((program)"create_object.pike")(); //importing the file containing the generalized case
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

//Creating object of a class that does not exists
int invalidClass(object me,object _Server,object...args)
{
	int pass=0;
	write("Creating a class that does not exists\n");
	mixed result = _Server->get_factory("NoClass");
	if(result == 0) pass =1;
	return pass;
}
/*
//Creating user
int createUser(object me,object _Server,object...args)
{
	int pass = 0;
	write("Creating a new user: ");
	mixed result = catch{_Server->get_factory("User")->execute((["name":"testUser1","pw":"password","email":"user@steam.com"])); };
	if(result ==0)pass=1;
	if(pass == 1)
	{
		write("passed\n");
		_Server->get_module("users")->get_user("testUser1")->delete();
	}	
	else write("failed\n");
	return pass;
}
*/
