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
		me->move(OBJ("/home/steam"));
		object obj = OBJ("/TestRoom");
		if(obj!=0)
		obj->delete();
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
		conn->login("root","steam",1);
		_Server = conn->SteamObj(0);
		me = _Server->get_module("users")->lookup("root");
		me->move(OBJ("/"));
		write("Creating test room\n\n");
		_Server->get_factory("Room")->execute((["name":"TestRoom"]))->move(OBJ("/"));
		me->move(OBJ("/TestRoom"));
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
			if(foo[i](me,_Server,conn)==1){
				success+=1;
			}
			
		}
		write("success: "+success+"\nfails: "+(cases-success)+"\n");
	}
}



int main(){
	Test move = Test("move",4);
	move->run();
	Test create = Test("create",3);
	create->run();
	Test getEnv = Test("getEnv",1);
	getEnv->run();
	Test perm = Test("userPermission",1);
	perm->run();

}
