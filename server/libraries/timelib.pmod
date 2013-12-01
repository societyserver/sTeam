constant montharr = ({ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
			   "Sep", "Oct", "Nov", "Dec" });

string utc_offset()
{
    int u = Calendar.now()->utc_offset();
    return sprintf( "%+03d%02d", -u/3600,max(u,-u)/60%60 );
}

string event_time(int tstamp)
{
    mapping t = localtime(tstamp);
    return sprintf( "[%02d/%3s/%04d:%02d:%02d:%02d %s]",
		    t->mday, montharr[t->mon], t->year+1900, 
		    t->hour, t->min, t->sec, utc_offset() );
}

string smtp_time(int tstamp)
{
    return Calendar.Second( tstamp )->format_smtp();
}

string log_time(int|void tstamp)
{
    if ( zero_type( tstamp ) ) tstamp = time();
    return Calendar.Second( tstamp )->format_time();
}
