#include "threads.h"
#include "interpret.h"

#if defined(PIKE_THREADS) && defined(_REENTRANT)
#define THREAD_SAFE_RUN(COMMAND)  do {\
  struct thread_state *state;\
 if((state = thread_state_for_id(th_self()))!=NULL) {\
    if(!state->swapped) {\
      COMMAND;\
    } else {\
      mt_lock(&interpreter_lock);\
      SWAP_IN_THREAD(state);\
      COMMAND;\
      SWAP_OUT_THREAD(state);\
      mt_unlock(&interpreter_lock);\
    }\
  }\
} while(0)
#else
#define THREAD_SAFE_RUN(COMMAND) COMMAND
#endif


void low_unserialize_string(char*, int);
void low_unserialize_float(char*);
void low_unserialize_integer(char*);
void low_unserialize_object(char*);
void low_unserialize_function(char*);
void low_unserialize_mapping(int num);
void low_unserialize_array(int num);
void low_unserialize_nothing();
