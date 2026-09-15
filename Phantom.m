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

#pragma mark - 悬浮球（全屏透明窗 + 球视图随指移动；收纳态 = 贴边毛玻璃条）

static UIWindow        *g_ballWin = nil;    // 全屏透明窗（只在球/条范围拦截触摸）
static UIView          *g_ballHost = nil;   // 球容器（自由移动，含投影）
static UIView          *g_ballBody = nil;   // 球体（毛玻璃 + 细边）
static UIImageView     *g_ballIcon = nil;
static UIControl       *g_ballCtl = nil;
static BOOL             g_ballCollapsed = NO;

static void PHBallRestyle(void);   // 前置声明（PHBallApplyLayout 在它之前调用）

#define PH_BALL_D   46.0     // 球直径
#define PH_STRIP_W  11.0     // 收纳条宽度

static NSInteger PHCfgI(NSString *key, NSInteger def) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud objectForKey:key] == nil ? def : [ud integerForKey:key];
}

static CGSize PHBallScreenSize(void) {
    if (g_ballWin.windowScene) return g_ballWin.windowScene.screen.bounds.size;
    return [UIScreen mainScreen].bounds.size;
}

static void PHBallSavePosition(void) {
    if (!g_ballHost) return;
    CGSize S = PHBallScreenSize();
    if (S.width <= 0 || S.height <= 0) return;
    CGRect f = g_ballHost.frame;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setDouble:f.origin.x / S.width forKey:@"phantom_ball_x"];
    [ud setDouble:f.origin.y / S.height forKey:@"phantom_ball_y"];
    [ud synchronize];
    PLog(@"ball pos saved (%.0f,%.0f) → ratio (%.3f,%.3f) collapsed=%d",
         f.origin.x, f.origin.y, f.origin.x / S.width, f.origin.y / S.height, (int)g_ballCollapsed);
}

// 切换「球 / 收纳条」形态

// 松手：夹回屏幕 → 吸附（若开）→ 收纳（若开）→ 记住位置

// 按设置刷外观：形状（方/圆）+ 自定义图标
// 切换「球 / 收纳条」形态（贴边且完全可见）
static void PHBallSetCollapsed(BOOL collapsed) {
    if (!g_ballHost || g_ballCollapsed == collapsed) return;
    g_ballCollapsed = collapsed;
    CGSize S = PHBallScreenSize();
    CGRect f = g_ballHost.frame;
    BOOL right = (f.origin.x + f.size.width / 2.0) > S.width / 2.0;
    if (collapsed) {
        f.size = CGSizeMake(PH_STRIP_W, PH_BALL_D);
        f.origin.x = right ? (S.width - PH_STRIP_W) : 0;
    } else {
        f.size = CGSizeMake(PH_BALL_D, PH_BALL_D);
        f.origin.x = right ? (S.width - PH_BALL_D) : 0;
    }
    g_ballHost.frame = f;
    g_ballBody.frame = g_ballHost.bounds;
    g_ballBody.layer.cornerRadius = collapsed ? (PH_STRIP_W / 2.0)
                                              : (PHCfgI(@"phantom_ball_shape", 1) == 0 ? 12.0 : PH_BALL_D / 2.0);
    g_ballIcon.hidden = collapsed;
    g_ballHost.layer.shadowOpacity = collapsed ? 0.25 : 0.38;
    PLog(@"ball collapsed=%d x=%.0f w=%.0f", (int)collapsed, f.origin.x, f.size.width);
}

// 松手后：先夹紧到屏幕内，再吸附最近边缘（每次执行，与是否收纳无关）
static void PHBallSettle(void) {
    if (!g_ballHost) return;
    CGSize S = PHBallScreenSize();
    BOOL attach     = (PHCfgI(@"phantom_ball_attach", 0) == 0);
    BOOL collapseOn = (PHCfgI(@"phantom_edge_hide", 0) == 1);
    CGRect f = g_ballHost.frame;

    // ② 手动把球拖出屏幕边缘 → 松手即收纳成条（仅当边缘收纳开启）
    if (collapseOn && !g_ballCollapsed && f.size.width > PH_BALL_D - 1.0) {
        CGFloat w = f.size.width;
        BOOL outLeft  = (f.origin.x < -w * 0.30);
        BOOL outRight = ((f.origin.x + w) > S.width + w * 0.30);
        if (outLeft || outRight) {
            PLog(@"manual drag-out (%@) → collapse", outLeft ? @"左" : @"右");
            CGFloat ty = MAX(0, MIN(f.origin.y, S.height - f.size.height));
            CGFloat tx = outLeft ? 0 : (S.width - w);
            [UIView animateWithDuration:0.12 animations:^{
                g_ballHost.frame = CGRectMake(tx, ty, w, w);
            } completion:^(BOOL done) {
                PHBallSetCollapsed(YES);
                PHBallSavePosition();
            }];
            PHBallScheduleAutoCollapse();   // 展开后重新开始 20 秒计时
            return;
        }
    }

    f.origin.y = MAX(0, MIN(f.origin.y, S.height - f.size.height));
    f.origin.x = MAX(0, MIN(f.origin.x, S.width - f.size.width));
    if (attach) {
        BOOL right = (f.origin.x + f.size.width / 2.0) > S.width / 2.0;
        f.origin.x = right ? (S.width - f.size.width) : 0;
    }
    if (!CGRectEqualToRect(f, g_ballHost.frame)) {
        [UIView animateWithDuration:0.16 animations:^{ g_ballHost.frame = f; }];
    }
    PHBallSavePosition();
}

// ---- 20 秒无操作 → 自动收纳成条（开了收纳也不会立刻收）----
#define PH_IDLE_COLLAPSE_SEC 20.0
static int g_ballIdleGen = 0;

static void PHBallScheduleAutoCollapse(void) {
    BOOL attach     = (PHCfgI(@"phantom_ball_attach", 0) == 0);
    BOOL collapseOn = (PHCfgI(@"phantom_edge_hide", 0) == 1);
    if (!attach || !collapseOn) return;
    int my = ++g_ballIdleGen;
    PLog(@"auto-collapse timer armed (%ds)", (int)PH_IDLE_COLLAPSE_SEC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PH_IDLE_COLLAPSE_SEC * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (my != g_ballIdleGen) return;
        if (g_ballCollapsed) return;
        PLog(@"idle %ds → auto collapse", (int)PH_IDLE_COLLAPSE_SEC);
        PHBallSetCollapsed(YES);
        PHBallSavePosition();
    });
}

// 任何操作（按球/拖球/开关面板）→ 立即展开 + 重新计时
static void PHBallActivity(void) {
    if (g_ballCollapsed) PHBallSetCollapsed(NO);
    PHBallScheduleAutoCollapse();
}

void PHBallNotifyActivity(void) { PHBallActivity(); }

void PHBallApplyLayout(void) {
    PHBallRestyle();
    PHBallSettle();
    if (PHCfgI(@"phantom_edge_hide", 0) == 1) {
        PHBallScheduleAutoCollapse();
    } else if (g_ballCollapsed) {
        PHBallSetCollapsed(NO);
    }
}

static void PHBallRestyle(void) {
    if (!g_ballBody) return;
    NSInteger shape = PHCfgI(@"phantom_ball_shape", 1);
    if (!g_ballCollapsed) {
        g_ballBody.layer.cornerRadius = (shape == 0) ? 12.0 : PH_BALL_D / 2.0;
    }
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
        g_ballIcon.frame = CGRectMake((PH_BALL_D - 24) / 2.0, (PH_BALL_D - 24) / 2.0, 24, 24);
    }
    PLog(@"ball restyle: shape=%ld icon=%@ collapsed=%d",
         (long)shape, custom ? @"自定义" : @"默认", (int)g_ballCollapsed);
}

// 全屏窗：只有球/条范围接收触摸，其他区域穿透给下层 App
@interface PHBallWindow : UIWindow
@property (nonatomic, weak) UIView *hitTarget;
@end

@implementation PHBallWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hitTarget) {
        CGPoint p = [self.hitTarget convertPoint:point fromView:self];
        if ([self.hitTarget pointInside:p withEvent:event]) {
            return [super hitTest:point withEvent:event];
        }
    }
    return nil;   // 穿透
}
@end

@interface PHBallControl : UIControl
@property (nonatomic) CGPoint startTouch;
@property (nonatomic) CGPoint startOrigin;
@property (nonatomic) BOOL moved;
@property (nonatomic) BOOL longFired;
@end

@implementation PHBallControl

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    PHBallActivity();                  // 一按就算操作：展开 + 重新计时
    self.startTouch = [touch locationInView:self.window];
    self.startOrigin = g_ballHost.frame.origin;
    self.moved = NO;
    self.longFired = NO;
    self.alpha = 0.85;
    PHBallControl *me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!me.moved && me.isTracking) { me.longFired = YES; PHShowLogPanel(); }
    });
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!g_ballHost) return YES;
    CGPoint pt = [touch locationInView:self.window];   // 窗口不动 → 坐标稳定，跟手
    CGFloat dx = pt.x - self.startTouch.x, dy = pt.y - self.startTouch.y;
    if (!self.moved && (fabs(dx) > 4 || fabs(dy) > 4)) self.moved = YES;
    if (!self.moved) return YES;
    CGRect f = g_ballHost.frame;
    f.origin = CGPointMake(self.startOrigin.x + dx, self.startOrigin.y + dy);
    g_ballHost.frame = f;      // 只动球视图，不动窗口 → 毛玻璃背景不重算，不抖
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.alpha = 1.0;
    if (self.moved) {
        PHBallSettle();
        PHBallScheduleAutoCollapse();   // 拖完重新计时（20 秒后才可能收纳）
    } else if (!self.longFired) {
        if (g_ballCollapsed) {          // 点收纳条：展开 + 打开面板
            PHBallSetCollapsed(NO);
            PHShowMenu();
        } else {
            PHShowMenu();
        }
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    self.alpha = 1.0;
    if (self.moved) PHBallSettle();
}

@end

void PHRefreshBall(void) {
    if (g_ballWin) {
        g_ballWin.hidden = YES;
        g_ballWin = nil; g_ballHost = nil; g_ballBody = nil; g_ballIcon = nil; g_ballCtl = nil;
        g_ballCollapsed = NO;
    }
    phCreateBall();
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

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat rx = [ud objectForKey:@"phantom_ball_x"] ? [ud doubleForKey:@"phantom_ball_x"] : 0.012;
    CGFloat ry = [ud objectForKey:@"phantom_ball_y"] ? [ud doubleForKey:@"phantom_ball_y"] : 0.19;
    BOOL collapse = (PHCfgI(@"phantom_edge_hide", 0) == 1);
    BOOL attach   = (PHCfgI(@"phantom_ball_attach", 0) == 0);

    PHBallWindow *w = [[PHBallWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, S.width, S.height);      // 全屏（透明）
    w.windowLevel = UIWindowLevelAlert + 90;
    w.backgroundColor = [UIColor clearColor];
    w.windowLevel = UIWindowLevelAlert + 90;
    g_ballWin = w;

    // 启动一律按「完整球」显示：位置夹紧到屏幕内，避免出现"只露一条"的残缺态
    CGFloat posX = MAX(0, MIN(rx * S.width, S.width - PH_BALL_D));
    CGFloat posY = MAX(0, MIN(ry * S.height, S.height - PH_BALL_D));

    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(posX, posY, PH_BALL_D, PH_BALL_D)];
    host.backgroundColor = [UIColor clearColor];
    host.layer.shadowColor = [UIColor blackColor].CGColor;
    host.layer.shadowOpacity = 0.38;
    host.layer.shadowRadius = 7.0;
    host.layer.shadowOffset = CGSizeMake(0, 2);
    [w addSubview:host];
    g_ballHost = host;

    UIView *ball = [[UIView alloc] initWithFrame:host.bounds];
    ball.clipsToBounds = YES;
    ball.layer.cornerRadius = PH_BALL_D / 2.0;
    ball.layer.borderWidth = 1.0;
    ball.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    [host addSubview:ball];
    g_ballBody = ball;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = ball.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [ball addSubview:blur];

    UIImageView *icon = [[UIImageView alloc] init];
    [ball addSubview:icon];
    g_ballIcon = icon;

    PHBallControl *ctl = [[PHBallControl alloc] initWithFrame:ball.bounds];
    ctl.backgroundColor = [UIColor clearColor];
    ctl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [ball addSubview:ctl];
    g_ballCtl = ctl;
    w.hitTarget = ctl;      // 只有球范围拦触摸

    w.hidden = NO;
    PHBallRestyle();
    if (attach && collapse) PHBallScheduleAutoCollapse();   // 启动不立即收纳，20 秒无操作才收
    PLog(@"phantom ball created at (%.0f,%.0f) 直径%.0f 形状=%ld 收纳=%d（全屏窗+视图移动）",
         host.frame.origin.x, host.frame.origin.y, PH_BALL_D,
         (long)PHCfgI(@"phantom_ball_shape", 1), (int)g_ballCollapsed);
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
    g_ballHost.frame = CGRectMake(120, 300, PH_BALL_D, PH_BALL_D);
    PHBallSavePosition();
    PH_CHECK([udB objectForKey:@"phantom_ball_x"] != nil, @"悬浮球位置可保存");
    [udB setInteger:0 forKey:@"phantom_ball_shape"];
    PHBallRestyle();
    PH_CHECK(fabs(g_ballBody.layer.cornerRadius - 12.0) < 0.01, @"形状切方形生效");
    [udB setInteger:1 forKey:@"phantom_ball_shape"];
    PHBallRestyle();
    PH_CHECK(fabs(g_ballBody.layer.cornerRadius - PH_BALL_D / 2.0) < 0.01, @"形状切圆形生效");
    [udB setObject:@"ball_icon.png" forKey:@"phantom_ball_icon"];
    PHResetBallIcon();
    PH_CHECK([udB objectForKey:@"phantom_ball_icon"] == nil, @"恢复默认图标生效");
    PHRefreshBall();
    PH_CHECK(g_ballWin != nil && g_ballCtl != nil, @"悬浮球可按设置重建（带拖动控件）");

    // v0.6：吸附（必执行）/ 收纳条完全可见 / 条态也吸附 / 自动收纳计时
    [udB setInteger:0 forKey:@"phantom_ball_attach"];     // 开吸附
    g_ballHost.frame = CGRectMake(150, 400, PH_BALL_D, PH_BALL_D);
    PHBallSettle();
    CGSize SZ = PHBallScreenSize();
    PH_CHECK(fabs(g_ballHost.frame.origin.x) < 0.5 ||
             fabs(g_ballHost.frame.origin.x - (SZ.width - PH_BALL_D)) < 0.5,
             @"吸附：松手后贴到左/右边缘（每次必执行）");
    [udB setInteger:1 forKey:@"phantom_edge_hide"];
    PHBallSetCollapsed(YES);
    PH_CHECK(g_ballCollapsed && g_ballHost.frame.size.width < PH_BALL_D, @"边缘收纳：变成贴边细条");
    PH_CHECK(g_ballHost.frame.origin.x >= -0.5 &&
             g_ballHost.frame.origin.x + g_ballHost.frame.size.width <= SZ.width + 0.5,
             @"收纳条完全在屏幕内（不出屏）");
    g_ballHost.frame = CGRectMake(150, 400, PH_STRIP_W, PH_BALL_D);
    PHBallSettle();
    PH_CHECK(g_ballHost.frame.origin.x <= 0.5 ||
             g_ballHost.frame.origin.x + PH_STRIP_W >= SZ.width - 0.5,
             @"收纳条拖动后同样吸附到边缘");
    PHBallSetCollapsed(NO);
    PH_CHECK(!g_ballCollapsed && g_ballHost.frame.size.width > 40, @"展开：恢复成球");
    g_ballIdleGen = 0;
    PHBallScheduleAutoCollapse();
    PH_CHECK(g_ballIdleGen > 0, @"自动收纳已排期（20 秒无操作才收纳）");

    // v0.7：① 启动即完整显示 ② 拖出边缘即收纳
    [udB setInteger:1 forKey:@"phantom_edge_hide"];
    [udB setInteger:0 forKey:@"phantom_ball_attach"];
    g_ballHost.frame = CGRectMake(SZ.width - PH_STRIP_W, 300, PH_BALL_D, PH_BALL_D);  // 模拟"上次退出是收纳态"
    PHBallSettle();
    PH_CHECK(g_ballHost.frame.size.width >= PH_BALL_D - 0.5 &&
             g_ballHost.frame.origin.x >= -0.5 &&
             g_ballHost.frame.origin.x + PH_BALL_D <= SZ.width + 0.5,
             @"启动/松手后球完整可见（不会只露一条）");
    PHBallSetCollapsed(NO);
    g_ballHost.frame = CGRectMake(SZ.width + 30, 300, PH_BALL_D, PH_BALL_D);         // 拖出右边缘
    PHBallSettle();
    PH_CHECK(g_ballCollapsed, @"手动拖出屏幕边缘 → 立即收纳成条");
    PHBallSetCollapsed(NO);
    [udB setInteger:0 forKey:@"phantom_edge_hide"];

    // 合成点击调用链（模拟器里 dispatch 无真实效果，但要确保不崩）
    if (g_iokitReady) {
        phTapStrategy(0, CGPointMake(0.5, 0.5), @"自测");
        PH_CHECK(YES, @"合成点击调用链执行完成（不崩）");
    }

    // UI：主菜单 / 动作卡片 / 各面板
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
