#import <Cocoa/Cocoa.h>
#import "../Sources/RDPBridge/GravixRDP.h"
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        __block bool finished = false;
        __block bool passed = false;
        GRSession *session = [[GRSession alloc] initWithConfiguration:@{@"host":@"127.0.0.1",@"port":@1,@"username":@"test",@"domain":@"",@"hardware":@YES,@"clipboard":@YES,@"dynamic":@YES,@"retina":@NO,@"width":@1280,@"height":@720,@"share":@""} password:@"test-only-not-a-real-password"];
        session.eventHandler = ^(NSString *event, NSString *detail) {
            NSLog(@"Probe: %@ %@", event, detail);
            if ([event isEqual:@"error"]) { passed = ![detail containsString:@"参数无效"]; finished = true; }
        };
        [session start];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
        while (!finished && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        [session stop];
        if (!finished || !passed) { fprintf(stderr,"Connection failure probe failed\n"); return 1; }
        puts("Connection failure probe passed");
    }
    return 0;
}
