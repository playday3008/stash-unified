#include "stashutils.h"
#include "versions.h"
#include <sys/mount.h>
#include <errno.h>
#include <string.h>

bool varHasNosuid(){
	struct statfs sfs;
	if (statfs("/private/var", &sfs) != 0)
		return true;
	return (sfs.f_flags & MNT_NOSUID) != 0;
}

bool tryRemoveNosuid(){
	if (!varHasNosuid()){
		printf("nosuid already clear on /private/var.\n");
		return true;
	}

	printf("Attempting to remount /private/var without nosuid...\n");

	struct statfs sfs;
	if (statfs("/private/var", &sfs) != 0){
		printf("Warning: statfs failed for /private/var.\n");
		return false;
	}

	int flags = sfs.f_flags;
	flags &= ~MNT_NOSUID;
	flags |= MNT_UPDATE;

	if (mount("hfs", "/private/var", flags, NULL) != 0){
		printf("Warning: Could not remount /private/var without nosuid (%s).\n",
			strerror(errno));
		printf("Setuid binaries on /var will not be stashed.\n");
		return false;
	}

	if (varHasNosuid()){
		printf("Warning: nosuid still active after remount attempt.\n");
		printf("Setuid binaries on /var will not be stashed.\n");
		return false;
	}

	printf("Successfully remounted /private/var without nosuid.\n");
	return true;
}

BOOL checkMount(){
	BOOL rebootNeeded = NO;
	NSString *mountOutput = outputFromCommand(@"/sbin/mount", @[]);
	NSArray *mountPoints = [mountOutput componentsSeparatedByString:@"\n"];
	for (NSString *mountPoint in mountPoints){
		if ([mountPoint rangeOfString:@" on /private/var "].location == NSNotFound)
			continue;
		if ([mountPoint rangeOfString:@"nosuid"].location != NSNotFound)
			rebootNeeded = YES;
	}
	return rebootNeeded;
}

void editFsTab(){
	if (!IS_IOS_BETWEEN(iOS_10_0, iOS_MaxSupported))
		return; //Only edit FSTab on iOS 10.0+ (up to 10.2.1 on arm64, 10.3.4 on armv7)

	NSString *fstab = [NSString stringWithContentsOfFile:@"/etc/fstab" encoding:NSASCIIStringEncoding error:nil];
	if (!fstab)
		return;

	NSMutableArray *mountPoints = [[fstab componentsSeparatedByString:@"\n"] mutableCopy];
	BOOL editNeeded = NO;
	NSUInteger idxToEdit = NSNotFound;

	for (NSString *mountPoint in mountPoints){
		if ([mountPoint rangeOfString:@" /private/var "].location == NSNotFound)
			continue;
		if ([mountPoint rangeOfString:@"nosuid"].location != NSNotFound){
			editNeeded = YES;
			idxToEdit = [mountPoints indexOfObject:mountPoint];
		}
	}

	if (editNeeded && idxToEdit != NSNotFound){
		copyFile(@"/etc/fstab",@"/etc/fstab.bak");
		// Remove nosuid from the existing line rather than replacing it wholesale,
		// so we don't assume a specific device/partition layout.
		NSString *origLine = [mountPoints objectAtIndex:idxToEdit];
		NSString *newLine = [origLine stringByReplacingOccurrencesOfString:@",nosuid" withString:@""];
		newLine = [newLine stringByReplacingOccurrencesOfString:@"nosuid," withString:@""];
		newLine = [newLine stringByReplacingOccurrencesOfString:@"nosuid" withString:@""];
		[mountPoints replaceObjectAtIndex:idxToEdit withObject:newLine];
		NSString *newFstab = [mountPoints componentsJoinedByString:@"\n"];
		[newFstab writeToFile:@"/etc/fstab" atomically:YES encoding:NSASCIIStringEncoding error:nil];
	}
}
