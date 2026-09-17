#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface PhuQuyGateOverlay : NSObject <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, copy) NSString *activeKey;
+ (instancetype)sharedInstance;
+ (void)showOverlayWithReason:(NSString *)reason;
+ (void)dismissOverlay;
- (void)startHeartbeat;
- (void)stopHeartbeat;
@end

@implementation PhuQuyGateOverlay
+ (instancetype)sharedInstance {
    static PhuQuyGateOverlay *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[PhuQuyGateOverlay alloc] init]; });
    return instance;
}

- (NSString *)getDeviceHWID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *hwid = [defaults stringForKey:@"phuquy_hwid"];
    if (!hwid || [hwid length] < 5) {
        hwid = [NSString stringWithFormat:@"HWID-%@", [[[NSUUID UUID] UUIDString] substringToIndex:13]];
        [defaults setObject:hwid forKey:@"phuquy_hwid"];
        [defaults synchronize];
    }
    return hwid;
}

+ (void)showOverlayWithReason:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        PhuQuyGateOverlay *gate = [PhuQuyGateOverlay sharedInstance];
        if (gate.overlayWindow) {
            gate.overlayWindow.hidden = NO;
            gate.overlayWindow.alpha = 1.0;
            [gate.overlayWindow makeKeyAndVisible];
            if (reason && gate.webView) {
                NSString *js = [NSString stringWithFormat:@"if (typeof showResult === 'function') { showResult(false, 400, '%@'); }", reason];
                [gate.webView evaluateJavaScript:js completionHandler:nil];
            }
            return;
        }
        
        CGRect bounds = [UIScreen mainScreen].bounds;
        gate.overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
        gate.overlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
        gate.overlayWindow.backgroundColor = [UIColor colorWithRed:3/255.0 green:7/255.0 blue:18/255.0 alpha:1.0];
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *controller = [[WKUserContentController alloc] init];
        [controller addScriptMessageHandler:gate name:@"phuquy"];
        [controller addScriptMessageHandler:gate name:@"onyxz"];
        config.userContentController = controller;
        
        gate.webView = [[WKWebView alloc] initWithFrame:bounds configuration:config];
        gate.webView.navigationDelegate = gate;
        gate.webView.scrollView.bounces = NO;
        gate.webView.backgroundColor = [UIColor colorWithRed:3/255.0 green:7/255.0 blue:18/255.0 alpha:1.0];
        gate.webView.opaque = NO;
        
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor colorWithRed:3/255.0 green:7/255.0 blue:18/255.0 alpha:1.0];
        [vc.view addSubview:gate.webView];
        
        gate.overlayWindow.rootViewController = vc;
        [gate.overlayWindow makeKeyAndVisible];
        
        NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"nhapkey" ofType:@"html"];
        if (htmlPath) {
            [gate.webView loadFileURL:[NSURL fileURLWithPath:htmlPath] allowingReadAccessToURL:[NSURL fileURLWithPath:[htmlPath stringByDeletingLastPathComponent]]];
        } else {
            [gate.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://phuquystore.site/nhapkey.html"]]];
        }
    });
}

+ (void)dismissOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        PhuQuyGateOverlay *gate = [PhuQuyGateOverlay sharedInstance];
        if (!gate.overlayWindow) return;
        [gate startHeartbeat];
        [UIView animateWithDuration:0.4 animations:^{
            gate.overlayWindow.alpha = 0.0;
        } completion:^(BOOL finished) {
            gate.overlayWindow.hidden = YES;
            gate.overlayWindow = nil;
            gate.webView = nil;
        }];
    });
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)msg {
    if ([msg.body isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)msg.body;
        NSString *action = d[@"action"];
        if ([action isEqualToString:@"unlock"]) {
            if (d[@"key"]) {
                self.activeKey = d[@"key"];
                [[NSUserDefaults standardUserDefaults] setObject:d[@"key"] forKey:@"phuquy_saved_key"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
            [PhuQuyGateOverlay dismissOverlay];
        } else if ([action isEqualToString:@"lock"]) {
            NSString *reason = d[@"reason"] ?: @"Key đã bị vô hiệu hóa hoặc hết hạn!";
            [self stopHeartbeat];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"phuquy_saved_key"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [PhuQuyGateOverlay showOverlayWithReason:reason];
        }
    }
}

- (void)startHeartbeat {
    [self stopHeartbeat];
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"phuquy_saved_key"];
    if (!savedKey) return;
    self.activeKey = savedKey;

    __weak typeof(self) weakSelf = self;
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 repeats:YES block:^(NSTimer *t) {
        [weakSelf performServerVerification];
    }];
}

- (void)stopHeartbeat {
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }
}

- (void)performServerVerification {
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"phuquy_saved_key"];
    if (!savedKey) {
        [self stopHeartbeat];
        [PhuQuyGateOverlay showOverlayWithReason:@"Key chưa được kích hoạt!"];
        return;
    }
    
    NSString *hwid = [self getDeviceHWID];
    NSString *urlString = [NSString stringWithFormat:@"https://phuquystore.site/api/onyxz_keys.php?action=check_key&key=%@&hwid=%@",
                          [savedKey stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                          [hwid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSURL *url = [NSURL URLWithString:urlString];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) return;
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
        if (http && http.statusCode != 200) {
            NSString *reason = @"Key không còn hợp lệ!";
            if (d) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                if (json && json[@"message"]) reason = json[@"message"];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopHeartbeat];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"phuquy_saved_key"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [PhuQuyGateOverlay showOverlayWithReason:reason];
            });
        }
    }] resume];
}
@end

__attribute__((constructor))
static void initPhuQuy() {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"phuquy_saved_key"];
        if (saved && [saved length] > 0) {
            [[PhuQuyGateOverlay sharedInstance] startHeartbeat];
            [[PhuQuyGateOverlay sharedInstance] performServerVerification];
        } else {
            [PhuQuyGateOverlay showOverlayWithReason:nil];
        }
    });
}
