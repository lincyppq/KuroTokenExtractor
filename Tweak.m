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
+ (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer;
+ (void)showIconSelector:(UIButton *)button;
+ (void)updateButtonIcon:(UIButton *)button withType:(NSString *)iconType;
@end

static UIButton *g_floatingButton = nil;

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
                          56, 56);

    // 亮青色背景（匹配库街区图标底色 #00EFE7）
    btn.backgroundColor = [UIColor colorWithRed:0.0/255.0
                                          green:239.0/255.0
                                           blue:231.0/255.0
                                          alpha:1.0];

    btn.layer.cornerRadius = 28;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    btn.layer.shadowOpacity = 0.15;
    btn.layer.shadowRadius = 8;
    btn.clipsToBounds = NO;

    // 尝试从宿主 App 加载图标
    UIImage *icon = nil;
    BOOL isHostIcon = NO;
    NSArray *possibleNames = @[
        @"KRAppIcon60x60",
        @"KRAppIcon76x76",
        @"AppIcon60x60",
        @"AppIcon",
        @"app_icon"
    ];

    for (NSString *name in possibleNames) {
        icon = [UIImage imageNamed:name];
        if (icon) {
            isHostIcon = YES;
            NSLog(@"[KuroTokenExtractor] ✓ Loaded icon: %@", name);
            break;
        }
    }

    // 兜底：使用 SF Symbol key.fill
    if (!icon) {
        if (@available(iOS 13.0, *)) {
            icon = [UIImage systemImageNamed:@"key.fill"];
            if (icon) {
                NSLog(@"[KuroTokenExtractor] Using fallback SF Symbol: key.fill");
            }
        }
    }

    // 创建图标视图
    if (icon) {
        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 28, 28)];
        iconView.image = icon;
        iconView.contentMode = UIViewContentModeScaleAspectFit;

        // 只对 SF Symbol 应用白色 tintColor，库街区图标保持原色
        if (!isHostIcon) {
            iconView.tintColor = [UIColor whiteColor];
        }

        iconView.userInteractionEnabled = NO;
        iconView.tag = 999;
        [btn addSubview:iconView];
    }

    [btn addTarget:self
            action:@selector(extractAndCopy)
  forControlEvents:UIControlEventTouchUpInside];

    // 添加长按手势切换图标
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
                                                initWithTarget:self
                                                action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [btn addGestureRecognizer:longPress];

    // 添加拖动手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];

    g_floatingButton = btn;

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

+ (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        UIButton *btn = (UIButton *)recognizer.view;
        [self showIconSelector:btn];
    }
}

+ (void)showIconSelector:(UIButton *)button {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"选择图标"
            message:@"请选择悬浮按钮显示的图标"
            preferredStyle:UIAlertControllerStyleActionSheet];

        // 选项 1: 宿主 App 图标
        [alert addAction:[UIAlertAction
            actionWithTitle:@"使用库街区图标"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * _Nonnull action) {
                [self updateButtonIcon:button withType:@"host"];
            }]];

        // 选项 2: SF Symbol
        if (@available(iOS 13.0, *)) {
            [alert addAction:[UIAlertAction
                actionWithTitle:@"使用系统图标（钥匙）"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction * _Nonnull action) {
                    [self updateButtonIcon:button withType:@"symbol"];
                }]];
        }

        [alert addAction:[UIAlertAction
            actionWithTitle:@"取消"
            style:UIAlertActionStyleCancel
            handler:nil]];

        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }

        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            alert.popoverPresentationController.sourceView = button;
            alert.popoverPresentationController.sourceRect = button.bounds;
        }

        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)updateButtonIcon:(UIButton *)button withType:(NSString *)iconType {
    // 移除旧图标
    UIView *oldIconView = [button viewWithTag:999];
    if (oldIconView) {
        [oldIconView removeFromSuperview];
    }
    [button setTitle:nil forState:UIControlStateNormal];

    if ([iconType isEqualToString:@"host"]) {
        // 从宿主 App 加载图标
        NSArray *possibleNames = @[
            @"KRAppIcon60x60",
            @"KRAppIcon76x76",
            @"AppIcon60x60",
            @"AppIcon",
            @"app_icon",
            @"icon_app",
            @"kjq_icon",
            @"launch_icon",
            @"img_app_launch_logo"
        ];

        UIImage *icon = nil;
        for (NSString *name in possibleNames) {
            icon = [UIImage imageNamed:name];
            if (icon) {
                NSLog(@"[KuroTokenExtractor] ✓ Switched to host icon: %@", name);
                break;
            }
        }

        if (icon) {
            UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 28, 28)];
            iconView.image = icon;
            iconView.contentMode = UIViewContentModeScaleAspectFit;
            // 库街区图标保持原色，不设置 tintColor（宿主图标自带颜色）
            iconView.userInteractionEnabled = NO;
            iconView.tag = 999;
            [button addSubview:iconView];
        } else {
            // 找不到就用系统图标兜底
            if (@available(iOS 13.0, *)) {
                UIImage *fallbackIcon = [UIImage systemImageNamed:@"key.fill"];
                if (fallbackIcon) {
                    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 28, 28)];
                    iconView.image = fallbackIcon;
                    iconView.contentMode = UIViewContentModeScaleAspectFit;
                    iconView.tintColor = [UIColor whiteColor];
                    iconView.userInteractionEnabled = NO;
                    iconView.tag = 999;
                    [button addSubview:iconView];
                    NSLog(@"[KuroTokenExtractor] Host icon not found, using SF Symbol");
                }
            }
        }

    } else if ([iconType isEqualToString:@"symbol"]) {
        // SF Symbol
        if (@available(iOS 13.0, *)) {
            UIImage *icon = [UIImage systemImageNamed:@"key.fill"];
            if (icon) {
                UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 28, 28)];
                iconView.image = icon;
                iconView.contentMode = UIViewContentModeScaleAspectFit;
                iconView.tintColor = [UIColor whiteColor];
                iconView.userInteractionEnabled = NO;
                iconView.tag = 999;
                [button addSubview:iconView];
                NSLog(@"[KuroTokenExtractor] ✓ Switched to SF Symbol");
            }
        }
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

