class SteamError {
#if constant(Error.Generic)
    inherit Error.Generic;
#endif

    string errmsg;
    array bt;
    void create(string msg, void|array backtrace) {
	errmsg = msg;
	bt = backtrace;
    }
    array backtrace() { return bt; }
    void set_message(string msg) { errmsg = msg; }
    string message() { return errmsg; }
    string describe() { return errmsg + "\n" + sprintf("%O\n", bt); }
    array cast(string type) {
	return ({ errmsg, bt });
    }
    
    mixed `[](int idx) {
	switch(idx) {
	case 0: return errmsg; 
	case 1: return bt;
	}
	return 0;
    }
    
    int is_generic_error() { return 1; }
    int display() { return 0; } // do not display this error message to a user
}

class SteamUserError {
    inherit SteamError;

    int display() { return 1; } // display this error directly
}
