/*
 * output.h
 *
 * output to the specified file
 *
 */


#ifndef OUTPUT_H
#define OUTPUT_H


struct OutBlock {
  struct OutBlock *nextBlock;
  void*   addr;
  int   size;
};


struct OutBlock* new_output();
void output(char *fmt, ...);
void output_cb(char *fmt, int len);
char* get_output(struct OutBlock* o);

#endif
