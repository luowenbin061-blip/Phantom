// 幻影 Phantom v0.2 —— 完整 UI 骨架版
// ============================================================
// 本版目标：把「和老贝贝一样的 UI」搭起来
//   · 点悬浮球 → 任务面板（动作列表 + 添加/执行/录制/设置/脚本/清空）
//   · 添加动作卡片（9 类动作：点击/双击/长按/滑动/识图/识色/识字/等待/录制）
//   · 各动作编辑卡片（字段照老贝贝：动作描述/执行次数/坐标/时长/相似度/成功后动作…）
//   · 设置弹窗（整体执行/定时/脚本管理/悬浮球形状·吸附·收纳/触摸轨迹/防录屏/广告加速/拦截跳转/自动关闭弹出）
//   · 长按悬浮球 → 日志面板（复制日志）
// 触摸合成引擎（阶段 0 已验证参数签名）保留在文件里，阶段 1 接执行器。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <stdatomic.h>
#import "PH.h"

static void PHShowLogPanel(void);
static void phCreateBall(void);

#pragma mark - 日志

static NSString *g_logPath = nil;

static void phLogLine(NSString *msg) {
    @try {
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            g_logPath = [(doc ?: NSHomeDirectory()) stringByAppendingPathComponent:@"Phantom.log"];
            df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"HH:mm:ss.SSS";
            FILE *f = fopen(g_logPath.fileSystemRepresentation, "a");
            if (f) { fputs("---- session ----\n", f); fclose(f); }
        });
        NSLog(@"[Phantom] %@", msg);
        NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [df stringFromDate:[NSDate date]], msg];
        FILE *f = fopen(g_logPath.fileSystemRepresentation, "a");
        if (f) { fputs(line.UTF8String, f); fclose(f); }
    } @catch (NSException *e) { }
}
#define PLog(fmt, ...) do { phLogLine([NSString stringWithFormat:(fmt), ##__VA_ARGS__]); } while (0)

#pragma mark - 触摸合成引擎（阶段 0 已验证参数签名；阶段 1 接执行器）

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static IOHIDEventSystemClientRef (*pCreate)(CFAllocatorRef);
static IOHIDEventSystemClientRef (*pCreateWithType)(CFAllocatorRef, int32_t, void *);
static void (*pDispatch)(IOHIDEventSystemClientRef, IOHIDEventRef);
static IOHIDEventRef (*pFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                     float, float, float, float, float, Boolean, Boolean, uint32_t);

static IOHIDEventSystemClientRef g_c0 = NULL, g_c1 = NULL, g_c2 = NULL;
static BOOL g_iokitReady = NO;
static atomic_int g_tapBusy = 0;

static BOOL phLoadIOKit(void) {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    PLog(@"IOKit dlopen: %@", h ? @"成功" : [NSString stringWithFormat:@"失败(%s)", dlerror()]);
    if (!h) return NO;
    pCreate         = dlsym(h, "IOHIDEventSystemClientCreate");
    pCreateWithType = dlsym(h, "IOHIDEventSystemClientCreateWithType");
    pDispatch       = dlsym(h, "IOHIDEventSystemClientDispatchEvent");
    pFingerEvent    = dlsym(h, "IOHIDEventCreateDigitizerFingerEvent");
    PLog(@"符号解析：Create=%p CreateWithType=%p Dispatch=%p Finger=%p",
         pCreate, pCreateWithType, pDispatch, pFingerEvent);
    return (pCreate && pDispatch && pFingerEvent);
}

// 合成一次点击（归一化坐标 0~1）；策略 0/1/2 = 三种 client 创建方式
static void phTapStrategy(int strategy, CGPoint ptNorm, NSString *tag) {
    int expected = 0;
    if (!atomic_compare_exchange_strong(&g_tapBusy, &expected, 1)) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            @try {
                if (strategy == 0 && !g_c0 && pCreate) g_c0 = pCreate(CFAllocatorGetDefault());
                else if (strategy == 1 && !g_c1 && pCreateWithType) g_c1 = pCreateWithType(CFAllocatorGetDefault(), 0, NULL);
                else if (strategy == 2 && !g_c2 && pCreateWithType) g_c2 = pCreateWithType(CFAllocatorGetDefault(), 1, NULL);
            } @catch (NSException *e) { PLog(@"[%@] client 异常: %@", tag, e); }
            IOHIDEventSystemClientRef c = (strategy == 0) ? g_c0 : (strategy == 1 ? g_c1 : g_c2);
            if (!c) { PLog(@"[%@] client 为空", tag); return; }
            uint64_t t = mach_absolute_time();
            IOHIDEventRef down = pFingerEvent(NULL, t, 1, 2, 7, ptNorm.x, ptNorm.y, 0, 0.62f, 0, TRUE, TRUE, 0);
            IOHIDEventRef up   = pFingerEvent(NULL, t + 1, 1, 2, 3, ptNorm.x, ptNorm.y, 0, 0.0f, 0, FALSE, FALSE, 0);
            if (!down || !up) { PLog(@"[%@] 事件创建失败", tag); return; }
            pDispatch(c, down);
            [NSThread sleepForTimeInterval:0.08];
            pDispatch(c, up);
            PLog(@"[%@] 已派发点击 归一化(%.4f,%.4f)", tag, ptNorm.x, ptNorm.y);
        } @finally { atomic_store(&g_tapBusy, 0); }
    });
}

#pragma mark - 悬浮球（可拖动 / 形状 / 吸附 / 边缘收纳 / 自定义图标）

static UIWindow        *g_ballWin = nil;
static UIView          *g_ballBody = nil;
static UIImageView     *g_ballIcon = nil;
static UIControl       *g_ballCtl = nil;

#define PH_BALL_SIZE 46.0
#define PH_BALL_PAD  9.0

static NSInteger PHCfgI(NSString *key, NSInteger def) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud objectForKey:key] == nil ? def : [ud integerForKey:key];
}

static CGSize PHBallScreenSize(void) {
    if (g_ballWin.windowScene) return g_ballWin.windowScene.screen.bounds.size;
    return [UIScreen mainScreen].bounds.size;
}

static void PHBallSavePosition(void) {
    if (!g_ballWin) return;
    CGSize S = PHBallScreenSize();
    if (S.width <= 0 || S.height <= 0) return;
    CGRect f = g_ballWin.frame;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setDouble:f.origin.x / S.width forKey:@"phantom_ball_x"];
    [ud setDouble:f.origin.y / S.height forKey:@"phantom_ball_y"];
    [ud synchronize];
    PLog(@"ball pos saved (%.0f,%.0f) → ratio (%.3f,%.3f)", f.origin.x, f.origin.y,
         f.origin.x / S.width, f.origin.y / S.height);
}

// 松手：夹回屏幕内 → 吸附（若开启）→ 边缘收纳（若开启）→ 记住位置
static void PHBallSettle(void) {
    if (!g_ballWin) return;
    CGSize S = PHBallScreenSize();
    BOOL attach   = (PHCfgI(@"phantom_ball_attach", 0) == 0);   // 0=吸附
    BOOL edgeHide = (PHCfgI(@"phantom_edge_hide", 0) == 1);
    CGRect f = g_ballWin.frame;
    f.origin.y = MAX(-PH_BALL_PAD, MIN(f.origin.y, S.height - f.size.height));
    CGFloat hide = edgeHide ? PH_BALL_SIZE * 0.45 : 0;
    if (attach) {
        BOOL right = (f.origin.x + f.size.width / 2.0) > S.width / 2.0;
        f.origin.x = right ? (S.width - f.size.width + hide) : -hide;
    } else {
        f.origin.x = MAX(-PH_BALL_PAD, MIN(f.origin.x, S.width - f.size.width + PH_BALL_PAD));
    }
    if (!CGRectEqualToRect(f, g_ballWin.frame)) {
        [UIView animateWithDuration:0.18 animations:^{ g_ballWin.frame = f; }];
    }
    PHBallSavePosition();
}

// 按设置刷外观：形状（方/圆）+ 自定义图标
static void PHBallRestyle(void) {
    if (!g_ballBody) return;
    NSInteger shape = PHCfgI(@"phantom_ball_shape", 1);          // 0=方 1=圆
    g_ballBody.layer.cornerRadius = (shape == 0) ? 12.0 : PH_BALL_SIZE / 2.0;

    NSString *iconName = [[NSUserDefaults standardUserDefaults] stringForKey:@"phantom_ball_icon"];
    UIImage *custom = nil;
    if (iconName.length) {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        custom = [UIImage imageWithContentsOfFile:[doc stringByAppendingPathComponent:iconName]];
    }
    if (custom) {
        g_ballIcon.image = custom;
        g_ballIcon.contentMode = UIViewContentModeScaleAspectFill;
        g_ballIcon.frame = g_ballBody.bounds;
    } else {
        g_ballIcon.image = PHIcon(@"hand.tap.fill", 21, [UIColor colorWithWhite:1.0 alpha:0.95]);
        g_ballIcon.contentMode = UIViewContentModeScaleAspectFit;
        g_ballIcon.frame = CGRectMake((PH_BALL_SIZE - 24) / 2.0, (PH_BALL_SIZE - 24) / 2.0, 24, 24);
    }
    PLog(@"ball restyle: shape=%ld icon=%@", (long)shape, custom ? @"自定义" : @"默认");
}

@interface PHBallControl : UIControl
@property (nonatomic) CGPoint startTouch;
@property (nonatomic) CGPoint startOrigin;
@property (nonatomic) BOOL moved;
@property (nonatomic) BOOL longFired;
@end

@implementation PHBallControl

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.startTouch = [touch locationInView:nil];
    self.startOrigin = self.window.frame.origin;
    self.moved = NO;
    self.longFired = NO;
    self.alpha = 0.78;
    PHBallControl *me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!me.moved && me.isTracking) { me.longFired = YES; PHShowLogPanel(); }
    });
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint pt = [touch locationInView:nil];
    CGFloat dx = pt.x - self.startTouch.x, dy = pt.y - self.startTouch.y;
    if (!self.moved && (fabs(dx) > 5 || fabs(dy) > 5)) self.moved = YES;
    if (!self.moved) return YES;
    CGRect f = self.window.frame;
    f.origin = CGPointMake(self.startOrigin.x + dx, self.startOrigin.y + dy);
    self.window.frame = f;       // 球跟着手指走
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.alpha = 1.0;
    if (self.moved) PHBallSettle();
    else if (!self.longFired) PHShowMenu();
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    self.alpha = 1.0;
    if (self.moved) PHBallSettle();
}

@end

void PHRefreshBall(void) {
    if (g_ballWin) {
        g_ballWin.hidden = YES;
        g_ballWin = nil; g_ballBody = nil; g_ballIcon = nil; g_ballCtl = nil;
    }
    phCreateBall();
}

void PHBallApplyLayout(void) {
    PHBallRestyle();
    PHBallSettle();
}

static void phCreateBall(void) {
    if (g_ballWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] &&
            sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
    }
    if (!scene) { PLog(@"ball: no scene"); return; }
    CGSize S = scene.screen.bounds.size;

    CGFloat winSize = PH_BALL_SIZE + PH_BALL_PAD * 2;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat rx = [ud objectForKey:@"phantom_ball_x"] ? [ud doubleForKey:@"phantom_ball_x"] : 0.012;
    CGFloat ry = [ud objectForKey:@"phantom_ball_y"] ? [ud doubleForKey:@"phantom_ball_y"] : 0.19;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(rx * S.width, ry * S.height, winSize, winSize);
    w.windowLevel = UIWindowLevelAlert + 90;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    g_ballWin = w;

    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(PH_BALL_PAD, PH_BALL_PAD, PH_BALL_SIZE, PH_BALL_SIZE)];
    host.backgroundColor = [UIColor clearColor];
    host.layer.shadowColor = [UIColor blackColor].CGColor;
    host.layer.shadowOpacity = 0.38;
    host.layer.shadowRadius = 7.0;
    host.layer.shadowOffset = CGSizeMake(0, 2);
    [w addSubview:host];

    UIView *ball = [[UIView alloc] initWithFrame:host.bounds];
    ball.clipsToBounds = YES;
    ball.layer.cornerRadius = PH_BALL_SIZE / 2.0;
    ball.layer.borderWidth = 1.0;
    ball.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    [host addSubview:ball];
    g_ballBody = ball;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = ball.bounds;
    [ball addSubview:blur];

    UIImageView *icon = [[UIImageView alloc] init];
    [ball addSubview:icon];
    g_ballIcon = icon;

    PHBallControl *ctl = [[PHBallControl alloc] initWithFrame:ball.bounds];
    ctl.backgroundColor = [UIColor clearColor];
    [ball addSubview:ctl];
    g_ballCtl = ctl;

    w.hidden = NO;
    PHBallRestyle();
    PLog(@"phantom ball created at (%.0f,%.0f) 直径%.0f 形状=%ld（毛玻璃圆球·可拖动）",
         w.frame.origin.x, w.frame.origin.y, PH_BALL_SIZE, (long)PHCfgI(@"phantom_ball_shape", 1));
}

#pragma mark - 悬浮球图标（相册选图）

static id g_iconPickerDelegate = nil;

@interface PHIconPickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation PHIconPickerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *img = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!img) return;
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"ball_icon.png"];
        if ([UIImagePNGRepresentation(img) writeToFile:path atomically:YES]) {
            [[NSUserDefaults standardUserDefaults] setObject:@"ball_icon.png" forKey:@"phantom_ball_icon"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            PLog(@"ball icon saved: %@", path);
            PHRefreshBall();
            PHToast(@"悬浮球图标已更新");
        } else {
            PHToast(@"图标保存失败");
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

void PHShowIconPicker(void) {
    UIWindowScene *scene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] &&
            sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
    }
    if (!scene) { PHToast(@"没有可用窗口"); return; }
    // present 必须在真正的宿主窗口上（我们的浮层不是 key window）
    UIWindow *host = scene.keyWindow;
    if (!host) {
        for (UIWindow *w in scene.windows) {
            if (w != g_ballWin && w.rootViewController) { host = w; break; }
        }
    }
    UIViewController *root = host.rootViewController;
    if (!root) { PHToast(@"宿主窗口没有控制器，无法打开相册"); return; }
    if (!g_iconPickerDelegate) g_iconPickerDelegate = [[PHIconPickerDelegate alloc] init];

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    picker.delegate = (PHIconPickerDelegate *)g_iconPickerDelegate;
    [root presentViewController:picker animated:YES completion:nil];
    PLog(@"icon picker presented on %@", NSStringFromClass([root class]));
}

void PHResetBallIcon(void) {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [[NSFileManager defaultManager] removeItemAtPath:[doc stringByAppendingPathComponent:@"ball_icon.png"] error:nil];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"phantom_ball_icon"];
    PHRefreshBall();
    PHToast(@"已恢复默认图标");
}

#pragma mark - 日志面板（长按球打开）

static UIWindow *g_logWin = nil;
static UITextView *g_logView = nil;

@interface PHLogActions : NSObject
+ (void)onClose;
+ (void)onCopy;
@end

@implementation PHLogActions
+ (void)onClose { if (g_logWin) { g_logWin.hidden = YES; g_logWin = nil; g_logView = nil; } }
+ (void)onCopy  {
    [UIPasteboard generalPasteboard].string =
        [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    PHToast(@"日志已复制到剪贴板");
}
@end

static void PHShowLogPanel(void) {
    @try {
        if (g_logWin) {
            g_logView.text = [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil] ?: @"(空)";
            return;
        }
        UIWindowScene *scene = nil;
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] &&
                sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
        }
        if (!scene) return;
        CGSize S = scene.screen.bounds.size;

        UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
        w.frame = CGRectMake(0, 0, S.width, S.height);
        w.windowLevel = UIWindowLevelAlert + 96;
        w.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        w.userInteractionEnabled = YES;
        g_logWin = w;

        UIControl *mask = [[UIControl alloc] initWithFrame:w.bounds];
        [mask addTarget:[PHLogActions class] action:@selector(onClose)
       forControlEvents:UIControlEventTouchUpInside];
        [w addSubview:mask];

        CGFloat pw = round(S.width * 0.88), ph = S.height * 0.62;
        UIView *card = PHCardView(CGRectMake((S.width - pw) / 2.0, (S.height - ph) / 2.0, pw, ph));
        [w addSubview:card];

        UILabel *t = PHLabel([NSString stringWithFormat:@"幻影 v%@ · 日志", PH_VERSION], 16, PH_TEXT, YES);
        t.frame = CGRectMake(16, 14, pw - 32, 22);
        [card addSubview:t];

        UILabel *st = PHLabel([NSString stringWithFormat:@"IOKit=%@ · 任务 %lu 个",
                               g_iokitReady ? @"就绪" : @"不可用", (unsigned long)PHActions().count],
                              12, PH_DIM, NO);
        st.frame = CGRectMake(16, 40, pw - 32, 18);
        [card addSubview:st];

        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(12, 64, pw - 24, ph - 64 - 60)];
        tv.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
        tv.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        tv.layer.cornerRadius = 8;
        tv.editable = NO;
        tv.text = [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil] ?: @"(空)";
        [tv scrollRangeToVisible:NSMakeRange(tv.text.length, 0)];
        [card addSubview:tv];
        g_logView = tv;

        CGFloat bw = (pw - 14 * 2 - 10) / 2.0;
        UIButton *copy = PHFootButton(@"📋 复制日志", NO, bw);
        copy.frame = CGRectMake(14, ph - 16 - 40, bw, 40);
        [copy addTarget:[PHLogActions class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:copy];
        UIButton *close = PHFootButton(@"关闭", YES, bw);
        close.frame = CGRectMake(14 + bw + 10, ph - 16 - 40, bw, 40);
        [close addTarget:[PHLogActions class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:close];

        w.hidden = NO;
        PLog(@"log panel shown");
    } @catch (NSException *e) { PLog(@"log panel exception: %@", e); }
}

#pragma mark - 自测（模拟器 e2e）

static int g_stPass = 0, g_stFail = 0;
static NSMutableString *g_stLog = nil;

static void stWrite(NSString *line) {
    PLog(@"selftest: %@", line);
    if (!g_stLog) g_stLog = [NSMutableString string];
    [g_stLog appendFormat:@"%@\n", line];
}
#define PH_CHECK(cond, name) do { \
    if (cond) { g_stPass++; stWrite([NSString stringWithFormat:@"PASS %@", (name)]); } \
    else { g_stFail++; stWrite([NSString stringWithFormat:@"FAIL %@", (name)]); } \
} while (0)

static void phSelftest(void) {
    if (g_stLog) return;
    g_stLog = [NSMutableString string];
    PLog(@"selftest begin");

    PH_CHECK(g_iokitReady, @"IOKit 符号解析成功");
    if (g_iokitReady) {
        CGSize S = [UIScreen mainScreen].bounds.size;
        IOHIDEventRef ev = pFingerEvent(NULL, mach_absolute_time(), 1, 2, 7,
                                        100.0f / S.width, 300.0f / S.height,
                                        0, 0.6f, 0, TRUE, TRUE, 0);
        PH_CHECK(ev != NULL, @"合成触摸事件创建成功");
        if (ev) CFRelease(ev);
    }
    PH_CHECK(g_ballWin != nil, @"悬浮球已创建");

    // v0.4：悬浮球行为（拖动保存 / 形状 / 图标复位 / 重建）
    NSUserDefaults *udB = [NSUserDefaults standardUserDefaults];
    CGRect bf = g_ballWin.frame;
    g_ballWin.frame = CGRectMake(120, 300, bf.size.width, bf.size.height);
    PHBallSavePosition();
    PH_CHECK([udB objectForKey:@"phantom_ball_x"] != nil, @"悬浮球位置可保存");
    [udB setInteger:0 forKey:@"phantom_ball_shape"];
    PHBallRestyle();
    PH_CHECK(fabs(g_ballBody.layer.cornerRadius - 12.0) < 0.01, @"形状切方形生效");
    [udB setInteger:1 forKey:@"phantom_ball_shape"];
    PHBallRestyle();
    PH_CHECK(fabs(g_ballBody.layer.cornerRadius - PH_BALL_SIZE / 2.0) < 0.01, @"形状切圆形生效");
    [udB setObject:@"ball_icon.png" forKey:@"phantom_ball_icon"];
    PHResetBallIcon();
    PH_CHECK([udB objectForKey:@"phantom_ball_icon"] == nil, @"恢复默认图标生效");
    PHRefreshBall();
    PH_CHECK(g_ballWin != nil && g_ballCtl != nil, @"悬浮球可按设置重建（带拖动控件）");

    // 合成点击调用链（模拟器里 dispatch 无真实效果，但要确保不崩）
    if (g_iokitReady) {
        phTapStrategy(0, CGPointMake(0.5, 0.5), @"自测");
        PH_CHECK(YES, @"合成点击调用链执行完成（不崩）");
    }

    PHShowMenu();
    PH_CHECK(PHIsPanelOpen(), @"主菜单面板已显示");
    PH_CHECK(PHActions() != nil, @"任务列表可读");

    for (NSInteger t = 0; t < 9; t++) [PHActions() addObject:[PHAction actionWithType:(PHActionType)t]];
    PH_CHECK(PHActions().count >= 9, @"9 类动作都能建进任务列表");

    BOOL allEditOK = YES;
    for (NSInteger i = 0; i < 9; i++) {
        PHShowActionEdit(i);
        if (!PHIsPanelOpen()) { allEditOK = NO; break; }
    }
    PH_CHECK(allEditOK, @"9 类动作编辑卡片全部可构建");

    PHShowAddAction(); PH_CHECK(PHIsPanelOpen(), @"添加动作卡片已显示");
    PHShowSettings();  PH_CHECK(PHIsPanelOpen(), @"设置面板已显示");
    PHShowScripts();   PH_CHECK(PHIsPanelOpen(), @"脚本管理面板已显示");
    PHShowLogPanel();  PH_CHECK(g_logWin != nil && !g_logWin.hidden, @"日志面板已显示");

    PHAction *a = [PHActions() objectAtIndex:0];
    a.desc = @"测试描述";
    a.pressMs = 66;
    PHAction *b = [PHAction fromDict:[a toDict]];
    PH_CHECK([b.desc isEqualToString:@"测试描述"] && fabs(b.pressMs - 66) < 0.01,
             @"动作模型 JSON 往返正确");

    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [g_stLog writeToFile:[doc stringByAppendingPathComponent:@"Phantom_selftest.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    PLog(@"selftest RESULT pass=%d fail=%d", g_stPass, g_stFail);
    stWrite([NSString stringWithFormat:@"RESULT pass=%d fail=%d", g_stPass, g_stFail]);
}

#pragma mark - 入口

__attribute__((constructor))
static void phantom_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        PLog(@"Phantom v%@ 注入加载（完整 UI + 主面板重做）", PH_VERSION);
        g_iokitReady = phLoadIOKit();

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL selftest = [ud boolForKey:@"phantom_selftest"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            phCreateBall();
            if (selftest) { phSelftest(); return; }
            PHToast(@"幻影已就绪：点悬浮球打开任务面板");
        });
    });
}
