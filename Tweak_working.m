#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// 全局变量存储拦截到的数据
static NSMutableDictionary *g_capturedHeaders = nil;

// Hook NSURLRequest 的 allHTTPHeaderFields
static NSDictionary* (*original_allHTTPHeaderFields)(id, SEL);

static NSDictionary* hooked_allHTTPHeaderFields(id self, SEL _cmd) {
    NSDictionary *headers = original_allHTTPHeaderFields(self, _cmd);

    if (headers && headers.count > 0) {
        // 提取关键字段
        if (headers[@"token"]) {
            [g_capturedHeaders setObject:headers[@"token"] forKey:@"token"];
            NSLog(@"[KuroTokenExtractor] ✓ Token captured");
        }
        if (headers[@"devCode"]) {
            [g_capturedHeaders setObject:headers[@"devCode"] forKey:@"devCode"];
            NSLog(@"[KuroTokenExtractor] ✓ devCode captured");
        }
        if (headers[@"userId"]) {
            [g_capturedHeaders setObject:headers[@"userId"] forKey:@"userId"];
        }
    }

    return headers;
}

@interface KuroTokenExtractorButton : UIButton
+ (void)installHook;
+ (void)showFloatingButton;
+ (void)extractAndCopy;
+ (NSString *)readTokenFromStorage;
+ (NSString *)readDeviceIdFromStorage;
+ (NSString *)readFromKeychain:(NSString *)key;
+ (void)showAlert:(NSString *)message;
+ (void)handlePan:(UIPanGestureRecognizer *)recognizer;
@end

@implementation KuroTokenExtractorButton

+ (void)installHook {
    Method method = class_getInstanceMethod([NSURLRequest class],
                                           @selector(allHTTPHeaderFields));
    if (method) {
        original_allHTTPHeaderFields = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)hooked_allHTTPHeaderFields);
        NSLog(@"[KuroTokenExtractor] ✓ Hook installed successfully!");
    } else {
        NSLog(@"[KuroTokenExtractor] ✗ Hook installation failed!");
    }
}

+ (void)showFloatingButton {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            if (w.isKeyWindow) {
                window = w;
                break;
            }
        }
        if (!window && windows.count > 0) {
            window = windows.firstObject;
        }
    }

    if (!window) {
        NSLog(@"[KuroTokenExtractor] ✗ No window found, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            [self showFloatingButton];
        });
        return;
    }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(window.bounds.size.width - 70,
                          window.bounds.size.height / 2,
                          60, 60);

    // 使用渐变背景（深蓝到浅蓝）
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = btn.bounds;
    gradient.colors = @[(id)[UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1.0].CGColor,
                       (id)[UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    gradient.cornerRadius = 30;
    [btn.layer insertSublayer:gradient atIndex:0];

    btn.layer.cornerRadius = 30;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.layer.shadowOpacity = 0.25;
    btn.layer.shadowRadius = 5;
    btn.clipsToBounds = NO;

    // 只显示 emoji 图标
    [btn setTitle:@"🔑" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:28];
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;

    [btn addTarget:self
            action:@selector(extractAndCopy)
  forControlEvents:UIControlEventTouchUpInside];

    // 添加拖动手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];

    [window addSubview:btn];
    window.windowLevel = UIWindowLevelAlert;

    NSLog(@"[KuroTokenExtractor] ✓ Floating button added!");
}

+ (void)extractAndCopy {
    NSString *token = g_capturedHeaders[@"token"] ?: @"";
    NSString *devCode = g_capturedHeaders[@"devCode"] ?: @"";
    NSString *userId = g_capturedHeaders[@"userId"] ?: @"";

    // 如果还没拦截到，尝试从存储读取
    if (token.length == 0) {
        token = [self readTokenFromStorage] ?: @"";
    }
    if (devCode.length == 0) {
        devCode = [self readDeviceIdFromStorage] ?: @"";
    }

    // 拼接格式: token,did
    NSString *result = [NSString stringWithFormat:@"%@,%@", token, devCode];

    // 复制到剪贴板
    [[UIPasteboard generalPasteboard] setString:result];

    // 显示详细信息
    NSString *tokenPreview = @"(未获取)";
    NSString *devCodePreview = @"(未获取)";

    if (token.length > 0) {
        tokenPreview = [token substringToIndex:MIN(20, token.length)];
        if (token.length > 20) {
            tokenPreview = [tokenPreview stringByAppendingString:@"..."];
        }
    }

    if (devCode.length > 0) {
        devCodePreview = [devCode substringToIndex:MIN(20, devCode.length)];
        if (devCode.length > 20) {
            devCodePreview = [devCodePreview stringByAppendingString:@"..."];
        }
    }

    NSString *message = [NSString stringWithFormat:
        @"✓ 已复制到剪贴板\n\n"
        @"Token: %@\n\n"
        @"DevCode: %@",
        tokenPreview,
        devCodePreview
    ];

    [self showAlert:message];

    NSLog(@"[KuroTokenExtractor] Result copied (length: %lu)", (unsigned long)result.length);
}

+ (NSString *)readTokenFromStorage {
    // 方法1: NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSArray *tokenKeys = @[@"token", @"user_token", @"userToken", @"TOKEN"];
    for (NSString *key in tokenKeys) {
        NSString *value = [defaults stringForKey:key];
        if (value && value.length > 0) {
            NSLog(@"[KuroTokenExtractor] Found token in NSUserDefaults: %@", key);
            return value;
        }
    }

    // 方法2: Keychain
    NSString *token = [self readFromKeychain:@"token"];
    if (token) {
        NSLog(@"[KuroTokenExtractor] Found token in Keychain");
        return token;
    }

    // 方法3: App Group UserDefaults
    NSUserDefaults *suite = [[NSUserDefaults alloc]
                            initWithSuiteName:@"com.kurogame.kjq"];
    if (suite) {
        for (NSString *key in tokenKeys) {
            NSString *value = [suite stringForKey:key];
            if (value && value.length > 0) {
                NSLog(@"[KuroTokenExtractor] Found token in App Group");
                return value;
            }
        }
    }

    return nil;
}

+ (NSString *)readDeviceIdFromStorage {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // 尝试多个可能的 key
    NSArray *keys = @[@"deviceId", @"deviceID", @"identifyId", @"devCode", @"device_id"];
    for (NSString *key in keys) {
        NSString *value = [defaults stringForKey:key];
        if (value && value.length > 0) {
            NSLog(@"[KuroTokenExtractor] Found deviceId in NSUserDefaults: %@", key);
            return value;
        }
    }

    // 从 Keychain
    NSString *deviceId = [self readFromKeychain:@"deviceId"];
    if (deviceId) {
        NSLog(@"[KuroTokenExtractor] Found deviceId in Keychain");
        return deviceId;
    }

    return nil;
}

+ (NSString *)readFromKeychain:(NSString *)key {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.kurogame.kjq",
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }

    return nil;
}

+ (void)showAlert:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"库街区 Token 提取器"
            message:message
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction
            actionWithTitle:@"确定"
            style:UIAlertActionStyleDefault
            handler:nil]];

        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }

        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *btn = recognizer.view;
    CGPoint translation = [recognizer translationInView:btn.superview];

    CGPoint newCenter = CGPointMake(btn.center.x + translation.x,
                                    btn.center.y + translation.y);

    // 限制在屏幕内
    CGFloat maxX = btn.superview.bounds.size.width - 35;
    CGFloat maxY = btn.superview.bounds.size.height - 35;

    newCenter.x = MAX(35, MIN(newCenter.x, maxX));
    newCenter.y = MAX(35, MIN(newCenter.y, maxY));

    btn.center = newCenter;
    [recognizer setTranslation:CGPointZero inView:btn.superview];

    if (recognizer.state == UIGestureRecognizerStateEnded) {
        // 吸附到边缘
        CGFloat screenWidth = btn.superview.bounds.size.width;
        [UIView animateWithDuration:0.3 animations:^{
            if (btn.center.x < screenWidth / 2) {
                btn.center = CGPointMake(50, btn.center.y);
            } else {
                btn.center = CGPointMake(screenWidth - 50, btn.center.y);
            }
        }];
    }
}

@end

// 使用 constructor 属性在 dylib 加载时自动执行
__attribute__((constructor))
static void KuroTokenExtractorInit(void) {
    NSLog(@"[KuroTokenExtractor] Plugin loaded!");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        g_capturedHeaders = [NSMutableDictionary dictionary];
        [KuroTokenExtractorButton installHook];
        [KuroTokenExtractorButton showFloatingButton];
    });
}

