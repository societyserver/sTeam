// this has been copied from Pike 7.6 ADT.Heap and ADT.Priority_queue
// because they don't implement the peek() method

#define SWAP(X,Y) do{ mixed tmp=values[X]; values[X]=values[Y]; values[Y]=tmp; }while(0)

class PriorityQueue {

static private array values=allocate(10);
static private int num_values;

static void adjust_down(int elem)
{
  while(1)
  {
    int child=elem*2+1;
    if(child >= num_values) break;
    
    if(child+1==num_values || values[child] < values[child+1])
    {
      if(values[child] < values[elem])
      {
	SWAP(child, elem);
	elem=child;
	continue;
      }
    } else {
      if(child+1 >= num_values) break;
      
      if(values[child+1] < values[elem])
      {
	SWAP(elem, child+1);
	elem=child+1;
	continue;
      }
    }
    break;
  }
}

static int adjust_up(int elem)
{
  int parent=(elem-1)/2;

  if(elem && values[elem] < values[parent])
  {
    SWAP(elem, parent);
    elem=parent;
    while(elem && (values[elem] < values[parent=(elem -1)/2]))
    {
      SWAP(elem, parent);
      elem=parent;
    }
    adjust_down(elem);
    return 1;
  }
  return 0;
}

//! @fixme
//!   Document this function
mixed push(int pri, mixed val)
{
  mixed handle;
  handle=elem(pri, val);

  if(num_values >= sizeof(values))
    values+=allocate(10+sizeof(values)/4);
  
  values[num_values++]=handle;
  adjust_up(num_values-1);
  return handle;
}

//! @fixme
//!   Document this function
void adjust(mixed value)
{
  int pos=search(values, value);
  if(pos>=0)
    if(!adjust_up(pos))
      adjust_down(pos);
}

//! Removes and returns the item on top of the heap,
//! which also is the smallest value in the heap.
mixed pop()
{
  mixed ret;
  if(!num_values)
    error("Heap underflow!\n");
  
  ret=values[0];
  if(sizeof(values) > 1)
  {
    num_values--;
    values[0]=values[num_values];
    values[num_values]=0;
    adjust_down(0);
    
    if(num_values * 3 + 10 < sizeof(values))
      values=values[..num_values+10];
  }
  return ret->value;
}

//! Returns the number of elements in the heap.
int _sizeof() { return num_values; }

// compat
int size() { return _sizeof(); }

class elem {
  int pri;
  mixed value;
  
  void create(int a, mixed b) { pri=a; value=b; }

  void set_pri(int p)
    {
      pri=p;
      adjust(this);
    }

  int get_pri() { return pri; }
  
  int `<(object o) { return pri<o->pri; }
  int `>(object o) { return pri>o->pri; }
  int `==(object o) { return pri==o->pri; }
};


//! @fixme
//!   Document this function
void adjust_pri(mixed handle, int new_pri)
{
  handle->pri=new_pri;
  adjust(handle);
}

mixed peek() {  if ( !num_values ) return ([])[0]; return values[0]->value; }

}
