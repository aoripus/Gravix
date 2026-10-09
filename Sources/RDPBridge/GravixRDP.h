#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@class GRSession;
@interface GRDesktopView : NSView <NSTextInputClient>
@property(nonatomic, weak, nullable) GRSession *session;
@end

@interface GRSession : NSObject
@property(nonatomic, readonly) GRDesktopView *desktopView;
// All event callbacks are delivered on the main thread.
@property(nonatomic, copy, nullable) void (^eventHandler)(NSString *event, NSString *detail);
- (instancetype)initWithConfiguration:(NSDictionary<NSString *, id> *)configuration password:(NSString *)password;
- (void)start;
- (void)stop;
- (void)sendControlAltDelete;
- (void)receiveFilesAtURL:(NSURL *)destination;
- (void)cancelTransfer;
- (void)publishFiles:(NSArray<NSURL *> *)files;
+ (NSString *)engineVersion;
@end
NS_ASSUME_NONNULL_END
