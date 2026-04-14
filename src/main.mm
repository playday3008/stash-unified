#import <stdio.h>
#import <unistd.h>
#import <getopt.h>
#import <spawn.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <objc/runtime.h>
#import "versions.h"

void stashAppMain();
void stashBinLibMain();
BOOL checkMount();
void editFsTab();
bool tryRemoveNosuid();

int main(int argc, char **argv, char **envp) {
	if (!IS_IOS_BETWEEN(iOS_9_2, iOS_MaxSupported)) {
		printf("Error: Unsupported iOS version. Not continuing.\n");
		return -1;
	}

	// Verify the filesystem is HFS+ — stashing is unsafe on APFS
	struct statfs sfs;
	if (statfs("/private/var", &sfs) != 0) {
		printf("Error: Unable to stat /private/var. Not continuing.\n");
		return -1;
	}
	if (strcmp(sfs.f_fstypename, "hfs") != 0) {
		printf("Error: /private/var is %s, not HFS+. Not continuing.\n", sfs.f_fstypename);
		return -1;
	}

	@autoreleasepool {
		bool needsReboot = checkMount();
		stashAppMain();
		editFsTab();
		tryRemoveNosuid();
		stashBinLibMain();
		if (needsReboot){
			printf("Reboot Needed to update mount points...\n");
			char *cydia_env = getenv("CYDIA");
			if (cydia_env != NULL){
				int cydiaFd = (int)strtoul(cydia_env, NULL, 10);
				if (cydiaFd != 0)
					write(cydiaFd, "finish:reboot", 13);
			}
		}
	}
	return 0;
}

// vim:ft=objc
