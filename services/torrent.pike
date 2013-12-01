inherit Service.Service;

#include <events.h>

static object updater;

void send_update(object obj, int id, string func, void|mixed args) 
{
  if ( !arrayp(args) )
    args = ({ id });
  else
    args = ({ id }) + args;

  send_cmd(obj, func, args, 1); // do not wait
}

void download(int id, string meta)
{
  Stdio.File f = Stdio.File("torrent/"+id+".torrent", "wct");
  f->write(meta);
  f->close();
  Protocols.Bittorrent.Torrent t=Protocols.Bittorrent.Torrent();
  t->downloads_update_status = lambda() {
      send_update(updater, id, "downloads_update_status");
  }; 

  // Callback when pieces status change (when we get new stuff): //
  t->pieces_update_status = lambda() {
			      send_update(updater, id, "piece_update");
			    };
  
  // Callback when peer status changes (connect, disconnect, choked...): //
  t->peer_update_status = lambda() {
			      send_update(updater, id, "peer_update");
			    };

  // Callback when download is completed:
  t->download_completed_callback= lambda() {   
				    send_update(updater, id, "finished");
				  };
  t->warning = lambda() {
		 send_update(updater, id, "warn");
	       };
  
  // Initiate targets from Torrent,
  // if target was created, no need to verify:
  write("Checking existing file:");
  function progress = lambda() {
      send_update(updater, id, "progress");
  };
  
  if (t->fix_targets(1,0,progress)==1)
    t->verify_targets(progress);

  // Open port to listen on,
  // we want to do this to be able to talk to firewalled peers:
  t->my_port=6800;
  t->open_port();

  // Ok, start calling tracker to get peers,
  // and tell about us:
  t->start_update_tracker();
  t->start_download();
}



void notify(mixed args)
{
}

void call_service(mixed args)
{
  switch(args[0]) {
  case "download":
      download(args[1], args[2]);
      break;
  case "run":
      updater = args[1];
      load_torrents();
      break;
  }
}

static void load_torrents()
{
  if ( !Stdio.exist("torrents") )
    mkdir("torrents");
  // read all torrents in torrents/
  foreach(get_dir("torrents"), string fname) {
    int id;
    Stdio.File f = Stdio.File("torrents/"+fname, "r");
    string meta = f->read();
    f->close();
    if ( sscanf(fname, "%d.torrent", id) )
      download(id, meta);
  }

}

static void run()
{
}

int main(int argc, array argv)
{
  init( "torrent", argv );
  start();
  return -17;
}
