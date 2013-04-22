inherit Service.Service;

#include <macros.h>
#include <events.h>

mixed getAttribute (object obj, string key) {
  return obj->query_attribute(key);
}

void call_service(object user, mixed args, int|void id) {
	werror("Graphic Service called with %O\n", args);
	
	object image = args[0];
	int xsize = args[1];
	int ysize = args[2];
	bool maintain_aspect = args[3];
	
	string result = Graphic.get_thumbnail(image, xsize, ysize, maintain_aspect, true);
	
	async_result(id, result);
	//if ( id ) async_result(result);
	//else callback_service(user, id, result);
}

static void run() {
}

static private void got_kill(int sig) {
	_exit(1);
}

int main(int argc, array argv)
{
	signal(signum("QUIT"), got_kill);
	init( "graphic", argv );
        start();
	return -17;
}

