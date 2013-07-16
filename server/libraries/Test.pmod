#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>
#include <configure.h>


/**
 * content of modules/factories sub-mapping:
 * mapping ([ object : ([ "exceptions":({ exception-obj, ... }),
                          "pending_calls":({ TestCard, ... }),
                          "started":time,
                          "finished":time,
                          "tests": ([ testname:([
                                        "result":"success/failed/skipped",
                                        "log":logmessages,
                                      ]), ... ]),
                       ]), ... ])
 */
static mapping tests = ([ ]);

static string current_testsuite_type = "";
static object current_testsuite = CALLER;

constant TEST_UNDEFINED = "(undefined)";
constant TEST_SKIPPED = "SKIPPED";
constant TEST_SUCCEEDED = "SUCCESS";
constant TEST_FAILED = "FAILED";

private static constant TEST_ORDER = ({ TEST_UNDEFINED, TEST_SKIPPED, TEST_SUCCEEDED, TEST_FAILED });

private static mapping make_testsuite ( object obj ) {
  if ( !objectp(obj) ) return UNDEFINED;
  obj = obj->this();
  mapping suite = tests[ obj ];
  if ( !mappingp(suite) ) {
    suite = ([ "exceptions":({ }),
               "pending_calls":({ }),
               "pending_threads":({ }),
               "started":0,
               "finished":0,
               "tests":([ ]),
               "tests_order":({ }),
            ]);
    tests[ obj ] = suite;
  }
  return suite;
}


/**
 * Records a single test result.
 *
 * @param test the name of the test within the testsuite
 * @param type "success", "failed" or "skipped"
 * @param msg the log message for that test
 * @param args parameters for the log message (as for sprintf or write)
 */
static void test_result ( string test, string type, string msg, mixed ... args ) {
  mapping suite = make_testsuite( CALLER->this() );

  mapping subtest = suite["tests"][ test ];
  if ( ! mappingp(subtest) ) {
    subtest = ([ "result":"", "log":"" ]);
    suite["tests"][ test ] = subtest;
    if ( search( suite["tests_order"], test ) < 0 )
      suite["tests_order"] += ({ test });
  }

  if ( search(TEST_ORDER, type) > search(TEST_ORDER, subtest["result"]) )
    subtest["result"] = type;
  if ( stringp(msg) && sizeof(msg)>0 )
    subtest["log"] += sprintf( "--- [%s] ----------\n"+msg, type, @args );
}


/**
 * Begin tests on an object. The object must have a "void test()" method,
 * which will be called to start the test. If you want additional test
 * functions to be called later, call Test.add_test_function(...) in your
 * test().
 *
 * @see add_test_function
 *
 * @param obj the object to test, or the calling object if none was specified
 */
int start_test ( object|void obj ) {
  if ( zero_type(obj) ) obj = CALLER;
  if ( !objectp(obj) || !functionp(obj->test) )
    return 0;
  obj = obj->this();

  mapping suite = tests[ obj ];
  if ( mappingp(suite) && suite["started"] != 0 )
    return 1;  // test already started
  if ( !mappingp(suite) )
    suite = make_testsuite( obj );
  if ( suite["started"] == 0 )
    suite["started"] = time();

  object first_test = TestCard( obj, obj->test, 0, 0);
  suite["pending_calls"] += ({ first_test });
  first_test->enqueue();
  return 1;
}


/**
 * Add a test function to be called after a certain delay.
 *
 * @param test_function the function to call later
 * @param delay the number of seconds after which to call the function
 * @param params params for the function
 */
void add_test_function ( function test_function, int delay, mixed ... params ) {
  object suite = CALLER->this();
  if ( !mappingp( tests[ suite ] ) ) {
    werror( "Test: %O wants to add a test function but hasn't been started "
            + "as a test!", suite );
    return;
  }
  if ( delay < 0 || delay > 30 ) {
    werror( "Test: Warning: test function %O scheduled in %d seconds!\n",
            test_function, delay );
  }
  tests[suite]["pending_calls"] += ({ TestCard( suite, test_function, delay,
                                                false, @params ) });
}


/**
 * Add a test function to be called in a thread after a certain delay.
 *
 * @param test_function the function to call later
 * @param delay the number of seconds after which to call the function
 * @param params params for the function
 */
void add_test_function_thread ( function test_function, int delay,
                                mixed ... params ) {
  object suite = CALLER->this();
  if ( !mappingp( tests[ suite ] ) ) {
    werror( "Test: %O wants to add a threaded test function but hasn't been "
            + "started as a test!", suite );
    return;
  }
  if ( delay < 0 || delay > 30 ) {
    werror( "Test: Warning: threaded test function %O scheduled in %d "
            + "seconds!\n", test_function, delay );
  }
  tests[suite]["pending_calls"] += ({ TestCard( suite, test_function, delay,
                                                true, @params ) });
}


private class TestCard {
  private object _suite;
  private function _func;
  private mixed _params;
  private int _delay;
  private bool _threaded;
  /** Create a new test function and plan it to run after a certain delay. */
  void create ( object suite, function test_function, int delay, bool threaded,
                mixed ... params ) {
    _suite = suite->this();
    _func = test_function;
    _delay = delay;
    _threaded = threaded;
    _params = params;
  }
  /** call_out the function with the planned delay. */
  void enqueue () {
    if ( functionp(_func) && objectp(_suite) )
      master()->f_call_out( run, _delay );
  }
  /** Run the test function and check whether the test suite is finished
   * or call_out the next test function. */
  void run () {
    if ( !objectp(_suite) ) {
      werror( "Test: test function with invalid test suite: %O\n", _suite );
      return;
    }
    if ( !functionp(_func) ) {
      werror( "Test: test function with invalid function: %O\n", _func );
      tests[_suite]["pending_calls"] -= ({ this_object() });
      return;
    }
    if ( _threaded ) {
      tests[_suite]["pending_calls"] -= ({ this_object() });
      tests[_suite]["pending_threads"] += ({ this_object() });
      master()->start_thread( run_thread, this_object() );
    }
    else {
    mixed err = catch ( _func( @_params ) );
    tests[_suite]["pending_calls"] -= ({ this_object() });
      if ( err ) {
        make_testsuite( _suite )["exceptions"] += ({ err });
      }
    }
    if ( sizeof( tests[_suite]["pending_calls"] ) > 0 )
      tests[_suite]["pending_calls"][0]->enqueue();
    else if ( sizeof( tests[_suite]["pending_threads"] ) < 1 )
      finish_test( _suite );
  }
  private void run_thread ( object testcard ) {
    object suite = testcard->get_suite();
    mixed params = testcard->get_params();
    function test_function = testcard->get_test_function();
    mixed err = catch( test_function( @params ) );
    tests[suite]["pending_threads"] -= ({ testcard });
    if ( err ) {
      make_testsuite( suite )["exceptions"] += ({ err });
    }
    if ( sizeof( tests[suite]["pending_calls"] ) < 1 &&
         sizeof( tests[suite]["pending_threads"] ) < 1 )
      finish_test( suite );
  }
  /** Return a string description of the call. */
  string describe () {
    return sprintf( "%O( %O )", _func, _params );
  }
  object get_suite () { return _suite; }
  function get_test_function () { return _func; }
  mixed get_params () { return _params; }
  int get_object_id() { return 0; }
  int get_object_class() { return 0;}
}


/**
 * Finishes tests on an object (which must have a test() method).
 *
 * @param obj the object to test, or the calling object if none was specified
 */
void finish_test ( object|void obj ) {
  if ( zero_type(obj) ) obj = CALLER;
  obj = obj->this();
  mapping suite = tests[ obj ];
  if ( mappingp(suite) ) suite["finished"] = time();
  if ( functionp(obj->test_cleanup) ) {
    catch( obj->test_cleanup() );
  }
}


/**
 * Returns the mapping of all started testsuites.
 */
mapping get_testsuites () {
  return tests;
}


/**
 * Returns a mapping of pending test suite test functions.
 *
 * @return pending test functions: ([ suite : ({ "func( args )" }) ])
 */
mapping get_pending_tests () {
  mapping result = ([ ]);
  foreach ( indices(tests), object suite ) {
    if ( sizeof(tests[suite]["pending_calls"]) < 1 &&
         sizeof(tests[suite]["pending_threads"]) < 1 )
      continue;
    result[suite] = ({ });
    foreach ( tests[suite]["pending_calls"], object test ) {
      result[suite] += ({ test->describe() });
    }
    foreach ( tests[suite]["pending_threads"], object test ) {
      result[suite] += ({ test->describe() });
    }
  }
  return result;
}


/**
 * Checks whether the tests on an object have finished.
 *
 * @param obj the object to test, or the calling object if none was specified
 */
bool is_test_finished ( object|void obj ) {
  if ( zero_type(obj) ) obj = CALLER;
  obj = obj->this();
  mapping suite = tests[ obj ];
  if ( !mappingp(suite) ) return false;
  if ((arrayp(suite["pending_calls"]) && sizeof(suite["pending_calls"])>0) ||
      (arrayp(suite["pending_threads"]) && sizeof(suite["pending_threads"])>0))
    return false;
  return (suite["started"] == 0) || (suite["finished"] != 0);
}


/**
 * Checks whether all started tests have finished.
 */
bool all_tests_finished () {
  foreach ( indices(tests), object suite ) {
    if ( !is_test_finished( suite ) )
      return false;
  }
  return true;
}


/**
 * Log a test, depending on the test result.
 * This is a convenience function, you can call it like this:
 *   Test.test( "testing length of str", sizeof(str) > 0 );
 *
 * @see succeeded
 * @see failed
 * @see skipped
 *
 * @param test the name or short description for the test
 * @param result the result value of the test (if this is == 0 then the
 *   test is considered failed, if it is != 0 then it is considered to
 *   have succeeded)
 * @param failure_msg a message to log if the test failed (if you want to
 *   log a message on success, you'll have to use the succeeded() and
 *   failed() methods instead)
 * @param args params for the message (like sprintf or write)
 * @return true if the test succeeded, false if it failed
 */
bool test ( string test, mixed result, void|string failure_msg, mixed ... args ) {
  if ( result ) {
    succeeded( test );
    return true;
  }
  else {
    failed( test, failure_msg, @args );
    return false;
  }
}


/**
 * Log a successful test.
 *
 * @see test
 * @see failed
 * @see skipped
 *
 * @param test the name or short description for the test
 * @param msg a message to log for the test
 * @param args params for the message (like sprintf or write)
 */
void succeeded ( string test, void|string msg, mixed ... args ) {
  test_result( test, TEST_SUCCEEDED,
               (stringp(msg) ? sprintf( msg, @args ) : "") );
}


/**
 * Log a failed test.
 *
 * @see test
 * @see succeeded
 * @see skipped
 *
 * @param test the name or short description for the test
 * @param msg a message to log for the test
 * @param args params for the message (like sprintf or write)
 */
void failed ( string test, void|string msg, mixed ... args ) {
  test_result( test, TEST_FAILED,
               (stringp(msg) ? sprintf( msg, @args ) : "") );
}


/**
 * Log a skipped test.
 *
 * @see test
 * @see succeeded
 * @see failed
 *
 * @param test the name or short description for the test
 * @param msg a message to log for the test
 * @param args params for the message (like sprintf or write)
 */
void skipped ( string test, void|string msg, mixed ... args ) {
  test_result( test, TEST_SKIPPED,
               (stringp(msg) ? sprintf( msg, @args ) : "") );
}


/**
 * Write test results, logs and statistics for all tests or a single
 * test suite.
 *
 * @param suite if unspecified, then the results of all test suites is
 *   returned, otherwise only the results for a single test suite are
 *   returned
 * @return a string containing a report on the tests, containing results,
 *   logs, errors and statistics
 */
string get_report ( void|object suite ) {
  string report = "";
  
  // for a single suite:
  if ( objectp(suite) ) {
    mapping statistics = get_statistics( suite );
    if ( !mappingp(statistics) ) return "";
    int total = statistics[TEST_SUCCEEDED] + statistics[TEST_FAILED]
      + statistics[TEST_SKIPPED] + statistics[TEST_UNDEFINED];
    if ( total < 1 && ( !arrayp(tests[suite]["exceptions"]) ||
	 sizeof(tests[suite]["exceptions"]) < 1 ) ) return "";

    string identifier = "";
    if ( functionp(suite->get_identifier) )
      identifier = suite->get_identifier();
    else
      identifier = sprintf( "%O", suite );
    report += sprintf( "===( %s )=== test results ===\nStarted: %s\n",
                       identifier, replace(ctime(tests[suite]["started"]),
                                           "\n","") );
    string unknown_str = "";
    if ( statistics[TEST_UNDEFINED] > 0 )
      unknown_str = sprintf( "* %d unknown\n", statistics[TEST_UNDEFINED] );
    report += sprintf( "%s :\n* %d failed\n* %d skipped\n* %d succeeded\n%s"
                       + "* %d total\n", identifier, statistics[TEST_FAILED],
                       statistics[TEST_SKIPPED], statistics[TEST_SUCCEEDED],
                       unknown_str, total );
    if ( sizeof(tests[suite]["exceptions"]) > 0 ) {
      report += sprintf( "* %d errors ocurred during the test:\n",
			 sizeof(tests[suite]["exceptions"]) );
      foreach ( tests[suite]["exceptions"], array err )
        report += sprintf( "%s\n%s-----\n", err[0], 
			   master()->describe_backtrace(err[1]) );
    }
    array tests_order = tests[suite]["tests_order"];
    // make sure all tests results are listed:
    foreach ( indices(tests[suite]["tests"]), string test )
      if ( search( tests_order, test ) < 0 ) tests_order += ({ test });
    // show results of the tests:
    foreach ( tests_order, string test ) {
      mapping test_entry = tests[suite]["tests"][test];
      string log = test_entry["log"];
      if ( stringp(log) && sizeof(log)>0 ) {
        log = "  " + replace( log, "\n", "\n  " );
        log += "\n";
      }
      report += sprintf( "* %s : %s\n%s", test, test_entry["result"], log );
    }
    report += sprintf( "Finished: %s (took %d seconds)\n",
                       replace(ctime(suite["finished"]),"\n",""),
                       suite["started"]-suite["finished"] );
    report += sprintf( "===( end: %s )=====\n", identifier );
    return report;
  }

  // for all test suites:
  report += "\n### TEST RESULTS ###############\n";
  array sorted_testsuites = indices(tests);
  array sorted_testsuites_names = ({ });
  foreach ( sorted_testsuites, object suite ) {
    if ( functionp(suite->get_identifier) )
      sorted_testsuites_names += ({ lower_case( suite->get_identifier() ) });
    else
      sorted_testsuites_names += ({ lower_case( sprintf( "%O", suite ) ) });
  }
  sort( sorted_testsuites_names, sorted_testsuites );
  foreach ( sorted_testsuites, object testsuite ) {
    string suite_report = get_report( testsuite );
    if ( stringp(suite_report) && sizeof(suite_report)>0 )
      report += suite_report + "\n";
  }
  mapping statistics = get_statistics();
  if ( mappingp(statistics) ) {
    report += "\n=== TOTAL ===============\n";
    int total = statistics[TEST_SUCCEEDED] + statistics[TEST_FAILED]
      + statistics[TEST_SKIPPED] + statistics[TEST_UNDEFINED];
    string unknown_str = "";
    if ( statistics[TEST_UNDEFINED] > 0 )
      unknown_str = sprintf( "* %d unknown\n", statistics[TEST_UNDEFINED] );
    report += sprintf( "* %d exceptions\n* %d failed\n* %d skipped\n"
		       + "* %d succeeded\n%s* %d total\n",
		       statistics["exceptions"], statistics[TEST_FAILED],
                       statistics[TEST_SKIPPED], statistics[TEST_SUCCEEDED],
                       unknown_str, total );
  }
  return report;
}


/**
 * Return statistics for all tests or a single test suite.
 *
 * @param suite if unspecified, then the total of all test results is
 *   returned, otherwise only the results for a single test suite are
 *   returned
 * @return a mapping with the results ([ TEST_SUCCEEDED:nr, TEST_FAILED:nr,
 *   TEST_SKIPPED:nr, TEST_UNDEFINED:nr ]), or UNDEFINED if a test suite was
 *   specified that wasn't tested
 */
mapping get_statistics ( void|object suite ) {
  mapping results = ([ TEST_SUCCEEDED:0, TEST_FAILED:0, TEST_SKIPPED:0,
                      TEST_UNDEFINED:0, "exceptions":0 ]);

  // single suite:
  if ( objectp(suite) ) {
    suite = suite->this();
    if ( !mappingp(tests[suite]) )
      return UNDEFINED;
    mapping subtests = tests[suite]["tests"];
    foreach ( indices(subtests), string test ) {
      string result = subtests[test]["result"];
      switch ( result ) {
        case TEST_SUCCEEDED:
          results[ TEST_SUCCEEDED ] += 1; break;
        case TEST_FAILED:
          results[ TEST_FAILED ] += 1; break;
        case TEST_SKIPPED:
          results[ TEST_SKIPPED ] += 1; break;
        default:
          results[ TEST_UNDEFINED ] += 1; break;
      }
    }
    if ( !arrayp(tests[suite]["exceptions"]) ) results[ "exceptions" ] = 0;
    else results[ "exceptions" ] = sizeof(tests[suite]["exceptions"]);
    return results;
  }

  // total of all suites:
  foreach ( indices(tests), object testsuite ) {
    mapping result = get_statistics( testsuite );
    if ( !mappingp(result) ) continue;
    results[ TEST_SUCCEEDED ] += result[ TEST_SUCCEEDED ];
    results[ TEST_FAILED ] += result[ TEST_FAILED ];
    results[ TEST_SKIPPED ] += result[ TEST_SKIPPED ];
    results[ TEST_UNDEFINED ] += result[ TEST_UNDEFINED ];
    results[ "exceptions" ] += result[ "exceptions" ];
  }
  return results;
}

int get_object_id() { return 0; }
int get_object_class() { return 0; }
