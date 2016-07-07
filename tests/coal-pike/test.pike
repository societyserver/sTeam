#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

class Testcase{
	string status;
	object code;
	int run(){
	
	}
}

class Test{
	string name;
	object _Server;
	object me;
	array(Testcase) cases;
	int failures;
	void create(string name,int totalCases){
		this.name=name;
		cases = allocate(totalCases);
		init();
	}
	void init(){
		string host = "127.0.0.1";
		int port = 1900;
		string server_path = "/usr/local/lib/steam";
		master()->add_include_path(server_path+"/server/include");
		master()->add_program_path(server_path+"/server/");
		master()->add_program_path(server_path+"/conf/");
		master()->add_program_path(server_path+"/spm/");
		master()->add_program_path(server_path+"/server/net/coal/");
		object conn = ((program)"../spm/client_base.pike")();
		conn->connect_server(host,port);
		conn->login("root","steam",1);
		_Server = conn->SteamObj(0);
		me = _Server->get_module("users")->lookup("root");
	}
	int run(){
		string n = name +".pike";
		object code = ((program)n)();
		array(function) foo = values(code);
//		code->testcase1(me,_Server);
		for(int i=0;i< sizeof(cases);i++){
		//	code->testcase+"i"();
			foo[i](me,_Server);
		}
	}
}



int main(){
	Test move = Test("move",1);
	move->run();
//	object test1 = ((program)"move.pike")();
//	int res = test1->testcase_move(me,_Server);
}
