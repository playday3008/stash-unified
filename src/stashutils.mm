#import <stdio.h>
#import <unistd.h>
#import <getopt.h>
#import <spawn.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <objc/runtime.h>

@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)launchPath;
- (void)setArguments:(NSArray *)arguments;
- (void)setStandardOutput:(NSPipe *)output;
- (void)setStandardError:(NSPipe *)output;
- (void)launch;
@end

BOOL isSymbolicLink(NSString *path){
	struct stat buf;
	if (lstat([path UTF8String], &buf) < 0)
		return false;
	return S_ISLNK(buf.st_mode);
}

bool isExecutable(NSString *path)
{
    struct stat st;

    if (stat([path UTF8String], &st) < 0)
        return false;
    if ((st.st_mode & S_IEXEC) != 0)
        return true;
    return false;
}

extern char **environ;

int run_cmd(const char *cmd, const char **argv)
{
    pid_t pid;
    int status;
    status = posix_spawn(&pid, cmd, NULL, NULL, (char * const *)argv, environ);
    if (status == 0) {
        if (waitpid(pid, &status, 0) != -1) {
            return status;
        } else {
            return -1;
        }
    } else {
        return -1;
    }
}

NSString *outputFromCommand(NSString *command, NSArray *arguments){
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:command];
	[task setArguments:arguments];
	NSPipe *pipe = [NSPipe pipe];
	[task setStandardOutput:pipe];
	NSPipe *pipeError = [NSPipe pipe];
	[task setStandardError:pipeError];
	NSFileHandle *fileHandle = [pipe fileHandleForReading];
	[task launch];
	NSData *data = [fileHandle readDataToEndOfFile];
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

bool copyFile(NSString *origPath, NSString *newPath){
	const char *cpArgv[] = {"cp","-Rp",[origPath UTF8String], [newPath UTF8String], NULL};
	if (run_cmd("/bin/cp", cpArgv) != 0){
		printf("Error: Unable to copy %s!\n",[origPath UTF8String]);
		return false;
	}
	return true;
}

bool deleteFile(NSString *path, int required){
	const char *rmArgv[] = {"rm","-rf", [path UTF8String], NULL};
	if (run_cmd("/bin/rm", rmArgv) != 0){
		if (required == 1)
			printf("Error: Unable to delete %s!\n",[path UTF8String]);
		return false;
	}
	return true;
}

bool linkFile(NSString *target, NSString *linkName){
	const char *lnArgv[] = {"ln","-s", [target UTF8String], [linkName UTF8String], NULL};
	if (run_cmd("/bin/ln", lnArgv) != 0){
		return false;
	}
	return true;
}

NSString *humanReadableFileSize(double convertedValue){
	int multiplyFactor = 0;
	NSArray *tokens = [NSArray arrayWithObjects:@"bytes",@"KB",@"MB",@"GB",@"TB",@"PB", @"EB", @"ZB", @"YB",nil];

	while (convertedValue > 1024) {
		convertedValue /= 1024;
		multiplyFactor++;
	}

	return [NSString stringWithFormat:@"%4.2f %@",convertedValue, [tokens objectAtIndex:multiplyFactor]];
}

bool stashFile(NSString *origPath, NSString *stashPath){
	if ([[NSFileManager defaultManager] fileExistsAtPath:stashPath]){
		if (!deleteFile(stashPath, 1))
			return false;
	}

	if (!copyFile(origPath, stashPath)){
		return false;
	}

	// Verify copy integrity for regular files (guards against partial writes
	// on nearly-full filesystems — the exact scenario stashing targets)
	{
		struct stat origSt, stashSt;
		if (stat([origPath UTF8String], &origSt) == 0 &&
		    !S_ISDIR(origSt.st_mode) &&
		    stat([stashPath UTF8String], &stashSt) == 0 &&
		    origSt.st_size != stashSt.st_size) {
			printf("Error: Size mismatch after copy for %s (%lld != %lld)\n",
				[origPath UTF8String], (long long)origSt.st_size, (long long)stashSt.st_size);
			deleteFile(stashPath, 0);
			return false;
		}
	}

	// Atomic stash: create symlink at temp path, then rename over original.
	// This avoids any window where the original path doesn't resolve.
	NSString *tempLink = [origPath stringByAppendingString:@".stash-tmp"];

	// Clean up leftover from a previous failed run
	if ([[NSFileManager defaultManager] fileExistsAtPath:tempLink])
		deleteFile(tempLink, 0);

	if (!linkFile(stashPath, tempLink)){
		return false;
	}

	BOOL isDirectory = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:origPath isDirectory:&isDirectory];

	if (!isDirectory) {
		// Regular file: rename() atomically replaces file with symlink
		if (rename([tempLink UTF8String], [origPath UTF8String]) != 0) {
			printf("Error: Atomic rename failed for %s\n", [origPath UTF8String]);
			deleteFile(tempLink, 0);
			return false;
		}
	} else {
		// Directory: can't rename a symlink over a directory, so rename
		// the directory away first, then place the symlink.
		NSString *oldPath = [origPath stringByAppendingString:@".stash-old"];
		if ([[NSFileManager defaultManager] fileExistsAtPath:oldPath])
			deleteFile(oldPath, 0);

		if (rename([origPath UTF8String], [oldPath UTF8String]) != 0) {
			printf("Error: Rename-away failed for %s\n", [origPath UTF8String]);
			deleteFile(tempLink, 0);
			return false;
		}
		if (rename([tempLink UTF8String], [origPath UTF8String]) != 0) {
			printf("Error: Rename-in failed for %s\n", [origPath UTF8String]);
			// Restore the original directory
			rename([oldPath UTF8String], [origPath UTF8String]);
			deleteFile(tempLink, 0);
			return false;
		}
		deleteFile(oldPath, 0);
	}
	return true;
}

// Copy ownership and mode from the stashed file onto the symlink itself.
// HFS+ on iOS honours symlink metadata for some access checks.
bool copyPermissions(NSString *linkPath, NSString *stashPath){
	if (![[NSFileManager defaultManager] fileExistsAtPath:linkPath])
		return false;
	if (![[NSFileManager defaultManager] fileExistsAtPath:stashPath])
		return false;

	struct stat st;
	if (stat([stashPath UTF8String], &st) < 0)
        return false;
    lchown([linkPath UTF8String], st.st_uid, st.st_gid);
    lchmod([linkPath UTF8String],st.st_mode);
    return true;
}

bool fileNameIsOk(NSString *fileName){
	if (!fileName)
		return false;
	if ([fileName isEqualToString:@""])
		return false;
	if ([fileName isEqualToString:[fileName lastPathComponent]])
		return true;
	return false;
}

bool deStashFile(NSString *origPath, NSString *stashPath){
	if ([[NSFileManager defaultManager] fileExistsAtPath:origPath]){
		if (!isSymbolicLink(origPath))
			return true;
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:stashPath])
		return false;

	if ([[NSFileManager defaultManager] fileExistsAtPath:origPath]){
		if (!deleteFile(origPath, 1)){
			return false;
		}
	}

	if (!copyFile(stashPath, origPath)){
		return false;
	}

	if (!deleteFile(stashPath, 0)){
		printf("Warning: Unable to delete %s! Will be removed on next run.\n",[stashPath UTF8String]);
	}
	return true;
}
