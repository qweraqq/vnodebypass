#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <inttypes.h>
#include <mach-o/loader.h>

int offset_init();

uint64_t proc_find(pid_t pidToFind);

//get vnode
uint64_t getVnodeAtPath(const char*);

//hide and show file using vnode
void hide_path(uint64_t);
void show_path(uint64_t);

//kernel write
void kwrite32(uint64_t va, uint32_t v);
void kwrite64(uint64_t va, uint64_t v);
//kernel read
uint64_t kread64(uint64_t va);
uint32_t kread32(uint64_t va);

int init_kernel(void);
bool isArm64e(void);
int get_root_by_krw(void);

NSString *locateJailbreakRoot(void);