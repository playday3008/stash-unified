#define AppsStash @"/var/stash/appsstash"

#import "signature.h"

int main(int argc, char **argv, char **envp) {
	@autoreleasepool {
		NSString *signature = [[NSString alloc] initWithString:@LOADER_SIGNATURE];
		[signature release];

		NSBundle *bundle = [NSBundle mainBundle];
		NSString *executableName = [[bundle executablePath] lastPathComponent];
		NSString *bundleName = [[bundle bundlePath] lastPathComponent];

		NSString *stashedBundlePath = [AppsStash stringByAppendingPathComponent:bundleName];

		NSString *stashedExecutablePath = [stashedBundlePath stringByAppendingPathComponent:executableName];

		NSLog(@"%@", stashedExecutablePath);

		execv([stashedExecutablePath cStringUsingEncoding:NSUTF8StringEncoding], argv); //chainload the app executable from stash path
	}
	return 0;
}

// vim:ft=objc
