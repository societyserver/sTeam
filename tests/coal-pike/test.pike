#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

object _Server;
object me;

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

int main(){
	init();
	object test1 = ((program)"move.pike")();
	int res = test1->testcase_move(me,_Server);
}
