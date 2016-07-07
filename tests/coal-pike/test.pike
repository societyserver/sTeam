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
	int pass = 0;
	string path = me->get_last_trail()->query_attribute("OBJ_PATH");
	write("Current location of user: "+path+"\n");
	me->move(OBJ("/new1"));
	write("Moving user to /new1\n");
	path = me->get_last_trail()->query_attribute("OBJ_PATH");
	write("New location of user: "+path+"\n");
	if(path=="/new1")pass=1;
	string result = (pass==1)?"passed\n":"fail\n";
	write("Test case 1: move user - "+result);
	me->move(OBJ("/home/root"));
}
