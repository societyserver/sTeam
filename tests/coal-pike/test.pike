#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

class Testcase{
	string status;
	object code;
	int run(){
	
	}
}

class Test{
	string name;    //Name of the the test case set
    
    //variables used to establish connection and interact with the server
	object _Server;
	object me;
	object conn;
    object _ServerRoot;
    object connRoot;
    
	//array(Testcase) cases;
	int cases;
    int failures;
	
    //Initialize the test case name and the number of test cases and call the init method
    void create(string name,int totalCases){
		this.name=name;
		cases = totalCases;
		init();
	}

    //Delete the objects created by the test suite and exit
	void destroy(){
        conn->login("root","steam",1);
        me->move(OBJ("/home/steam"));
        _Server->get_module("users")->get_user("TestUser")->delete();
        conn->logout();
//		write("===============================\n");
	}

    //Establist a connection to the server and initialize the server variables
	void init(){
		string host = "127.0.0.1";
		int port = 1900;
		string server_path = "/usr/local/lib/steam";
		master()->add_include_path(server_path+"/server/include");
		master()->add_program_path(server_path+"/server/");
		master()->add_program_path(server_path+"/conf/");
		master()->add_program_path(server_path+"/spm/");
		master()->add_program_path(server_path+"/server/net/coal/");
		conn = ((program)"../spm/client_base.pike")();
		conn->connect_server(host,port);
		connRoot = ((program)"../spm/client_base.pike")();
        connRoot->connect_server(host,port);
        connRoot->login("root","steam",1);
        _ServerRoot = connRoot->SteamObj(0);
		_Server = conn->SteamObj(0);
        createUser("TestUser","password");
        conn->login("TestUser","password",1);
		me = _Server->get_module("users")->lookup("TestUser");
		_Server->get_factory("Room")->execute((["name":"TestRoom"]))->move(OBJ("/home/TestUser"));
		me->move(OBJ("/home/TestUser"));
		write("===============================\n");
	}

    //Fetch the file containing the code for the test.
    //Get all the test cases and execute them one by one
    //record the status of the test
	int run(){
		string n = name +".pike";
		object code = ((program)n)(); // Fetch the code for test cases as an object
		array(function) foo = values(code);
		int success = 0;
		for(int i=0;i< cases;i++){  //loop through the cases and execute them one by one
			if(foo[i](me,_Server,conn,createUser)==1){
				success+=1;
			}
			
		}
		write("success: "+success+"\nfails: "+(cases-success)+"\n");
	}

    int createUser(string name,string password){
        int result = 0;
        object user = _ServerRoot->get_module("users")->get_user(name);
        if(user)user->delete();
        mixed res = catch{
            _ServerRoot->get_factory("User")->execute((["name":name,"pw":password]));
            _ServerRoot->get_module("users")->get_user(name)->activate_user();
        };
        if (res=0){write("Error creating user");return 0;}
        else return 1;
    }
}



int main(){
	Test move = Test("move",4);
	move->run();
	Test create = Test("create",2);
	create->run();
	Test getEnv = Test("getEnv",1);
	getEnv->run();

	Test perm = Test("userPermission",1);
	perm->run();
}
