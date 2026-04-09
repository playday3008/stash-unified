#import <stdio.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import "stashutils.h"

#define AppsPath @"/Applications/"
#define AppsStash @"/var/stash/appsstash"
#define BinsPath @"/usr/bin/"
#define BinsStash @"/var/stash/usrbin"
#define LibsPath @"/usr/lib/"
#define LibsStash @"/var/stash/usrlib"

// Paths our preinst stashes via Cydia's move.sh
static NSArray *moveShPaths;

unsigned long long directorySize(NSString *path){
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:path])
		return 0;
	unsigned long long total = 0;
	NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
	NSString *file;
	while ((file = [enumerator nextObject])){
		NSString *fullPath = [path stringByAppendingPathComponent:file];
		if (isSymbolicLink(fullPath))
			continue;
		NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
		if (attrs)
			total += [attrs fileSize];
	}
	return total;
}

bool checkRootSpace(){
	struct statfs sfs;
	if (statfs("/", &sfs) != 0){
		printf("Warning: Unable to check free space on /. Proceeding anyway.\n");
		return true;
	}

	unsigned long long freeBytes = (unsigned long long)sfs.f_bavail * sfs.f_bsize;
	unsigned long long needed = 0;

	needed += directorySize(AppsStash);
	needed += directorySize(BinsStash);
	needed += directorySize(LibsStash);

	// Include our move.sh entries
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *entries = [fm contentsOfDirectoryAtPath:@"/var/stash" error:nil];
	for (NSString *entry in entries){
		if (![entry hasSuffix:@".lnk"])
			continue;
		NSString *lnkPath = [@"/var/stash" stringByAppendingPathComponent:entry];
		NSString *origPath = [NSString stringWithContentsOfFile:lnkPath encoding:NSUTF8StringEncoding error:nil];
		if (!origPath || ![moveShPaths containsObject:origPath])
			continue;
		needed += directorySize([lnkPath stringByDeletingPathExtension]);
	}

	if (needed > freeBytes){
		printf("Error: Not enough free space on / to de-stash.\n");
		printf("  Need: %s, Available: %s\n",
			[humanReadableFileSize((double)needed) UTF8String],
			[humanReadableFileSize((double)freeBytes) UTF8String]);
		printf("  Free up space on the root partition before removing this package.\n");
		return false;
	}

	printf("Space check OK: need %s, have %s free on /\n",
		[humanReadableFileSize((double)needed) UTF8String],
		[humanReadableFileSize((double)freeBytes) UTF8String]);
	return true;
}

void deStashApps(){
	NSFileManager *fm = [NSFileManager defaultManager];

	if (![fm fileExistsAtPath:AppsStash])
		return;

	printf("De-stashing apps...\n");

	NSArray *apps = [fm contentsOfDirectoryAtPath:AppsStash error:nil];
	for (NSString *appName in apps){
		NSString *appStash = [AppsStash stringByAppendingPathComponent:appName];
		NSString *appPath = [AppsPath stringByAppendingPathComponent:appName];

		BOOL isDir = NO;
		if (![fm fileExistsAtPath:appStash isDirectory:&isDir] || !isDir)
			continue;
		if (![fm fileExistsAtPath:appPath isDirectory:&isDir] || !isDir)
			continue;

		printf("  %s\n", [appName UTF8String]);

		NSArray *contents = [fm contentsOfDirectoryAtPath:appStash error:nil];
		for (NSString *fileName in contents){
			NSString *stashedPath = [appStash stringByAppendingPathComponent:fileName];
			NSString *origPath = [appPath stringByAppendingPathComponent:fileName];

			// Skip symlinks in the stash dir — back-references to
			// Info.plist and icon files that were never stashed
			if (isSymbolicLink(stashedPath))
				continue;

			if (isSymbolicLink(origPath)){
				// Stashed file/dir (symlink → stash); also covers iOS 10.3+
				// executables that were symlinked instead of loader-replaced
				deStashFile(origPath, stashedPath);
			} else if ([fm fileExistsAtPath:stashedPath] && [fm fileExistsAtPath:origPath]){
				// iOS 9.x-10.2.x: executable was replaced with the loader
				// stub (not a symlink), force-replace with real binary
				deleteFile(origPath, 1);
				if (copyFile(stashedPath, origPath))
					deleteFile(stashedPath, 0);
			}
		}

		// Only remove if all files were successfully de-stashed
		rmdir([appStash UTF8String]);
	}

	rmdir([AppsStash UTF8String]);
}

void deStashDir(NSString *realDir, NSString *stashDir, const char *label){
	NSFileManager *fm = [NSFileManager defaultManager];

	if (![fm fileExistsAtPath:stashDir])
		return;

	printf("De-stashing %s...\n", label);

	NSArray *files = [fm contentsOfDirectoryAtPath:stashDir error:nil];
	for (NSString *fileName in files){
		NSString *stashedPath = [stashDir stringByAppendingPathComponent:fileName];
		NSString *origPath = [realDir stringByAppendingPathComponent:fileName];
		deStashFile(origPath, stashedPath);
	}

	rmdir([stashDir UTF8String]);
}

void deStashMoveSh(){
	NSFileManager *fm = [NSFileManager defaultManager];

	if (![fm fileExistsAtPath:@"/var/stash"])
		return;

	NSArray *entries = [fm contentsOfDirectoryAtPath:@"/var/stash" error:nil];
	for (NSString *entry in entries){
		if (![entry hasSuffix:@".lnk"])
			continue;

		NSString *lnkPath = [@"/var/stash" stringByAppendingPathComponent:entry];
		NSString *origPath = [NSString stringWithContentsOfFile:lnkPath encoding:NSUTF8StringEncoding error:nil];

		if (!origPath)
			continue;

		// Only touch entries our preinst created
		if (![moveShPaths containsObject:origPath])
			continue;

		NSString *stashDir = [lnkPath stringByDeletingPathExtension];
		if (![fm fileExistsAtPath:stashDir])
			continue;

		NSString *contentDir = [stashDir stringByAppendingPathComponent:[origPath lastPathComponent]];

		if (isSymbolicLink(origPath) && [fm fileExistsAtPath:contentDir]){
			printf("De-stashing %s...\n", [origPath UTF8String]);
			deleteFile(origPath, 1);
			rename([contentDir UTF8String], [origPath UTF8String]);
			deleteFile(stashDir, 0);
			deleteFile(lnkPath, 0);
		}
	}
}

void restoreFsTab(){
	if (![[NSFileManager defaultManager] fileExistsAtPath:@"/etc/fstab.bak"])
		return;

	printf("Restoring /etc/fstab from backup...\n");
	deleteFile(@"/etc/fstab", 1);
	copyFile(@"/etc/fstab.bak", @"/etc/fstab");
	deleteFile(@"/etc/fstab.bak", 0);
}

int main(int argc, char **argv, char **envp){
	@autoreleasepool {
		// dpkg passes the action as argv[1]
		if (argc >= 2){
			NSString *action = [NSString stringWithUTF8String:argv[1]];
			if (![action isEqualToString:@"remove"] && ![action isEqualToString:@"purge"])
				return 0;
		}

		moveShPaths = @[
			@"/Library/PreferenceBundles",
			@"/Library/PreferenceLoader",
			@"/usr/local/bin",
			@"/usr/local/lib",
			@"/usr/share/llvm"
		];

		printf("StashUnified: de-stashing files...\n");

		if (!checkRootSpace())
			return 1;

		deStashApps();
		deStashDir(BinsPath, BinsStash, "binaries");
		deStashDir(LibsPath, LibsStash, "libraries");
		deStashMoveSh();
		restoreFsTab();

		// Clean up /var/stash if empty
		rmdir("/var/stash");

		printf("StashUnified: de-stash complete.\n");
	}
	return 0;
}

// vim:ft=objc
