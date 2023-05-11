#include "kernel.h"
#include <dlfcn.h>

//set offset
#define kCFCoreFoundationVersionNumber_iOS_12_0    (1535.12)
#define kCFCoreFoundationVersionNumber_iOS_13_0_b2 (1656)
#define kCFCoreFoundationVersionNumber_iOS_13_0_b1 (1652.20)
#define kCFCoreFoundationVersionNumber_iOS_14_0_b1 (1740)
#define kCFCoreFoundationVersionNumber_iOS_15_0 (1854)
#define kCFCoreFoundationVersionNumber_iOS_15_2 (1856.105)

uint32_t off_p_pid = 0;
uint32_t off_p_pfd = 0;
uint32_t off_fd_ofiles = 0;
uint32_t off_fp_fglob = 0;
uint32_t off_fg_data = 0;
uint32_t off_vnode_iocount = 0;
uint32_t off_vnode_usecount = 0;
uint32_t off_vnode_vflags = 0;
uint32_t off_p_ucred = 0;
uint64_t savedThisProcUcreds = 0;

int offset_init() {
	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_15_0) {
        // ios 15
        printf("iOS 15.x offset selected!!!\n");
        off_p_pid = 0x68; //proc_pid v
        off_p_pfd = 0x100;  //
        off_fd_ofiles = 0x0; //?
        off_fp_fglob = 0x10;
        off_fg_data = 0x38; //_fg_get_vnode + 10, LDR X0, [X0,#0x38]
        off_vnode_iocount = 0x64; //vnode_iocount v
        off_vnode_usecount = 0x60; //vnode_usecount v
        off_vnode_vflags = 0x54; //_vnode_isvroot, _vnode_issystem, _vnode_isswap... LDR W8, [X0,#0x54] v
		off_p_ucred = 0xD8;

		if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_15_2) {
			off_p_pfd = 0xd8; 
			off_p_ucred = 0x0;
		}

        return 0;
    }

	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_14_0_b1) {
		// ios 14
		printf("iOS 14.x offset selected!!!\n");
		off_p_pid = 0x68;
		off_p_pfd = 0xf8;
		off_fd_ofiles = 0x0;
		off_fp_fglob = 0x10;
		off_fg_data = 0x38;
		off_vnode_iocount = 0x64;
		off_vnode_usecount = 0x60;
		off_vnode_vflags = 0x54;
		return 0;
	}

	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0_b2) {
		// ios 13
		printf("iOS 13.x offset selected!!!\n");
		off_p_pid = 0x68;
		off_p_pfd = 0x108;
		off_fd_ofiles = 0x0;
		off_fp_fglob = 0x10;
		off_fg_data = 0x38;
		off_vnode_iocount = 0x64;
		off_vnode_usecount = 0x60;
		off_vnode_vflags = 0x54;
		return 0;
	}

	if(kCFCoreFoundationVersionNumber <= kCFCoreFoundationVersionNumber_iOS_13_0_b1
	   && kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_12_0) {
		//ios 12
		printf("iOS 12.x offset selected!!!\n");
		off_p_pid = 0x60;
		off_p_pfd = 0x100;
		off_fd_ofiles = 0x0;
		off_fp_fglob = 0x8;
		off_fg_data = 0x38;
		off_vnode_iocount = 0x64;
		off_vnode_usecount = 0x60;
		off_vnode_vflags = 0x54;
		return 0;
	}

	return -1;
}

//get vnode
uint64_t get_vnode_with_file_index(int file_index, uint64_t proc) {

	void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	printf("libjb: %p\n", libjb);
	void *libjb_run_unsandboxed = dlsym(libjb, "run_unsandboxed");
	printf("libjb_run_unsandboxed: %p\n", libjb_run_unsandboxed);

	printf("borrow_ucreds: before -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

	void (*run_unsandboxed)(void (^block)(void)) = libjb_run_unsandboxed;

	static uint64_t vnode = 0;
	run_unsandboxed(^{
		printf("borrow_ucreds: changed -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

		uint64_t filedesc = kernel_read64(proc + off_p_pfd);
		uint64_t fileproc = kernel_read64(filedesc + off_fd_ofiles);

		uint64_t openedfile = 0;
    	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_15_0)
        	openedfile = kernel_read64(filedesc + (8 * file_index));
    	else
        	openedfile = kernel_read64(fileproc + (8 * file_index));

		uint64_t fileglob = kernel_read64(openedfile + off_fp_fglob);
		vnode = kernel_read64(fileglob + off_fg_data);

		uint32_t usecount = kernel_read32(vnode + off_vnode_usecount);
		uint32_t iocount = kernel_read32(vnode + off_vnode_iocount);

		printf("get_vnode_with_file_index: before -> usecount = 0x%x, iocount = 0x%x\n", usecount, iocount);

		kernel_write32(vnode + off_vnode_usecount, usecount + 1);
		kernel_write32(vnode + off_vnode_iocount, iocount + 1);

		printf("get_vnode_with_file_index: after -> usecount = 0x%x, iocount = 0x%x\n", kernel_read32(vnode + off_vnode_usecount), kernel_read32(vnode + off_vnode_iocount));

	});

	printf("borrow_ucreds: reverted -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

	dlclose(libjb);

	return vnode;
}

//hide and show file using vnode
#define VISSHADOW 0x008000
void hide_path(uint64_t vnode){

	void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	printf("libjb: %p\n", libjb);
	void *libjb_run_unsandboxed = dlsym(libjb, "run_unsandboxed");
	printf("libjb_run_unsandboxed: %p\n", libjb_run_unsandboxed);

	printf("borrow_ucreds: before -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

	void (*run_unsandboxed)(void (^block)(void)) = libjb_run_unsandboxed;

	run_unsandboxed(^{
		printf("borrow_ucreds: changed -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

		uint32_t v_flags = kernel_read32(vnode + off_vnode_vflags);
		printf("hide_path: before -> v_flags = %x\n", v_flags);
		kernel_write32(vnode + off_vnode_vflags, (v_flags | VISSHADOW));
	
		v_flags = kernel_read32(vnode + off_vnode_vflags);
		printf("hide_path: after -> v_flags = %x\n", v_flags);
	});
}

void borrow_ucreds(uint64_t this_proc, uint64_t kern_proc) {

	// void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	// printf("libjb: %p\n", libjb);
	// void *libjb_run_unsandboxed = dlsym(libjb, "run_unsandboxed");
	// printf("libjb_run_unsandboxed: %p\n", libjb_run_unsandboxed);

	// printf("borrow_ucreds: before -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

	// void (*run_unsandboxed)(void (^block)(void)) = libjb_run_unsandboxed;

	// run_unsandboxed(^{
	// 	printf("borrow_ucreds: changed -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));
	// });

	// printf("borrow_ucreds: reverted -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));

	// dlclose(libjb);

	// uint64_t this_ucreds = kernel_read64(this_proc + off_p_ucred);
	// uint64_t kern_ucreds = kernel_read64(kern_proc + off_p_ucred);
	// printf("borrow_ucreds: before -> this_ucreds = 0x%llx, kern_ucreds = 0x%llx\n", this_ucreds, kern_ucreds);

	// void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	// printf("libjb: %p\n", libjb);
	// void *libjb_proc_set_ucred = dlsym(libjb, "proc_set_ucred");
	// printf("libjb_proc_set_ucred: %p\n", libjb_proc_set_ucred);
	// void (*proc_set_ucred)(uint64_t proc_ptr, uint64_t ucred_ptr) = libjb_proc_set_ucred;
	// proc_set_ucred(this_proc, kern_ucreds);

	// savedThisProcUcreds = this_ucreds;
	// printf("borrow_ucreds: after -> this_ucreds = 0x%llx, kern_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred), kernel_read64(kern_proc + off_p_ucred));
	// dlclose(libjb);


	// void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	// printf("libjb: %p\n", libjb);
	// void *libjb_kwrite_ptr = dlsym(libjb, "kwrite_ptr");
	// printf("libjb_kwrite_ptr: %p\n", libjb_kwrite_ptr);
	// void (*kwrite_ptr)(uint64_t kaddr, uint64_t pointer, uint16_t salt) = libjb_kwrite_ptr;

	// uint64_t this_ucreds = kernel_read64(this_proc + off_p_ucred);
	// uint64_t kern_ucreds = kernel_read64(kern_proc + off_p_ucred);

	// printf("borrow_ucreds: before -> this_ucreds = 0x%llx, kern_ucreds = 0x%llx\n", this_ucreds, kern_ucreds);

	// kwrite_ptr(this_proc + off_p_ucred, kern_ucreds, 0x84E8);

	// printf("borrow_ucreds: after -> this_ucreds = 0x%llx, kern_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred), kernel_read64(kern_proc + off_p_ucred));

	// savedThisProcUcreds = this_ucreds;
	
	// dlclose(libjb);
}

void revert_ucreds(uint64_t this_proc) {
	// uint64_t this_ucreds = kernel_read64(this_proc + off_p_ucred);
	// printf("borrow_ucreds: before -> this_ucreds = 0x%llx\n", this_ucreds);

	// void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	// printf("libjb: %p\n", libjb);
	// void *libjb_proc_set_ucred = dlsym(libjb, "proc_set_ucred");
	// printf("libjb_proc_set_ucred: %p\n", libjb_proc_set_ucred);
	// void (*proc_set_ucred)(uint64_t proc_ptr, uint64_t ucred_ptr) = libjb_proc_set_ucred;
	// proc_set_ucred(this_proc, savedThisProcUcreds);

	// savedThisProcUcreds = 0;
	// printf("borrow_ucreds: after -> this_ucreds = 0x%llx\n", kernel_read64(this_proc + off_p_ucred));
	// dlclose(libjb);


	// void *libjb = dlopen("/var/jb/basebin/libjailbreak.dylib", RTLD_NOW);
	// printf("libjb: %p\n", libjb);
	// void *libjb_kwrite_ptr = dlsym(libjb, "kwrite_ptr");
	// printf("libjb_kwrite_ptr: %p\n", libjb_kwrite_ptr);
	// void (*kwrite_ptr)(uint64_t kaddr, uint64_t pointer, uint16_t salt) = libjb_kwrite_ptr;

	// uint64_t this_ucreds = kernel_read64(this_proc + off_p_ucred);
	// printf("revert_ucreds: before -> this_ucreds = 0x%llx\n", this_ucreds);
	// kwrite_ptr(this_proc + off_p_ucred, savedThisProcUcreds, 0x84E8);
	// printf("revert_ucreds: after -> this_ucreds = 0x%llx\n", this_ucreds);

	// savedThisProcUcreds = 0;
	// dlclose(kwrite_ptr);
}

void show_path(uint64_t vnode){
	uint32_t v_flags = kernel_read32(vnode + off_vnode_vflags);
	kernel_write32(vnode + off_vnode_vflags, (v_flags &= ~VISSHADOW));
}

int init_kernel() {

  printf("======= init_kernel =======\n");

  if(dimentio_init(0, NULL, NULL) != KERN_SUCCESS) {
    printf("failed dimentio_init!\n");
		return 1;
  }

//	if(init_tfp0() != KERN_SUCCESS) {
//		printf("failed get_tfp0!\n");
//		return 1;
//	}
//
	if(kbase == 0) {
		printf("failed get_kbase\n");
		return 1;
	}

	kern_return_t err = offset_init();
	if (err) {
		printf("offset init failed: %d\n", err);
		return 1;
	}

	return 0;
}
