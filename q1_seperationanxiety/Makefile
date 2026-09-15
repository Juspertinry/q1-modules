# Out-of-tree build. KDIR must point at a kernel tree matching the device or
# insmod refuses on vermagic. Module.symvers carries the symbol CRCs recovered
# from the prebuilt .ko, since Meta ships none and the running kernel hides them.
obj-m := seperationanxiety.o

KDIR ?= $(HOME)/oculus-linux-kernel
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-android-
SYMVERS ?= $(PWD)/Module.symvers

all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		KBUILD_EXTRA_SYMBOLS=$(SYMVERS) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean
