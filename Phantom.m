// 幻影 Phantom v0.1 —— 触摸合成验证（go/no-go 门）
// ============================================================
// 目标：验证 TrollFools 注入环境下，IOKit 私有 API 能否合成"系统级触摸"。
// 这是自研连点器（参考老贝贝功能思路，代码全新实现）的第一块地基。
//
// 验证方法（自证闭环）：
//   注入后 5/8/11 秒，用三种不同策略（IOHIDEventSystemClient 的三种创建方式）
//   分别对「幻影自己的悬浮球中心」发一次合成点击。
//   哪个策略把悬浮球点开了（面板弹出），哪个策略就是有效策略。
//
// 零依赖：全部私有符号运行时 dlsym 解析，不缺一崩；模拟器（无真实 IOKit）自动降级。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <stdatomic.h>

#define PH_VERSION @"0.1"

@interface PhantomActions : NSObject
+ (void)onBallTap;
+ (void)onCopy;
+ (void)onRerun;
+ (void)onPanelClose;
@end

// ---------------- 日志 ----------------
static NSString *g_logPath = nil;

static void PLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void PLog(NSString *fmt, ...) {
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
        NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [df stringFromDate:[NSDate date]], [NSString stringWithFormat:fmt, ##__VA_ARGS__]];
        NSLog(@"[Phantom] %@", [NSString stringWithFormat:fmt, ##__VA_ARGS__]);
        FILE *f = fopen(g_logPath.fileSystemRepresentation, "a");
        if (f) { fputs(line.UTF8String, f); fclose(f); }
    } @catch (NSException *e) { }
}

// ---------------- IOKit 私有符号（运行时解析） ----------------
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static IOHIDEventSystemClientRef (*pCreate)(CFAllocatorRef);
static IOHIDEventSystemClientRef (*pCreateWithType)(CFAllocatorRef, int32_t, void *);
static void (*pDispatch)(IOHIDEventSystemClientRef, IOHIDEventRef);
static IOHIDEventRef (*pFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                     float, float, float, float, float, Boolean, Boolean, uint32_t);

static IOHIDEventSystemClientRef g_c0 = NULL, g_c1 = NULL, g_c2 = NULL;
static BOOL g_iokitReady = NO;
static atomic_int  g_busy = 0;   // 防止点击序列重入

static BOOL phLoadIOKit(void) {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    PLog(@"IOKit dlopen: %@", h ? @"成功" : [NSString stringWithFormat:@"失败(%s)", dlerror()]);
    if (!h) return NO;
    pCreate       = dlsym(h, "IOHIDEventSystemClientCreate");
    pCreateWithType = dlsym(h, "IOHIDEventSystemClientCreateWithType");
    pDispatch     = dlsym(h, "IOHIDEventSystemClientDispatchEvent");
    pFingerEvent  = dlsym(h, "IOHIDEventCreateDigitizerFingerEvent");
    PLog(@"符号解析：Create=%p CreateWithType=%p Dispatch=%p Finger=%p",
         pCreate, pCreateWithType, pDispatch, pFingerEvent);
    return (pCreate && pDispatch && pFingerEvent);
}

// ---------------- 合成点击 ----------------
// Digitizer 事件掩码：Range=1 Touch=2 Position=4；坐标用归一化 0~1
static void phTapWithClient(IOHIDEventSystemClientRef client, CGPoint pt, NSString *tag) {
    if (!client) { PLog(@"[%@] client 为空，跳过", tag); return; }
    CGSize S = [UIScreen mainScreen].bounds.size;
    float nx = (float)(pt.x / S.width), ny = (float)(pt.y / S.height);
    uint64_t t = mach_absolute_time();
    IOHIDEventRef down = pFingerEvent(NULL, t, 1, 2, 7, nx, ny, 0, 0.62f, 0, TRUE, TRUE, 0);
    IOHIDEventRef up   = pFingerEvent(NULL, t + 1, 1, 2, 3, nx, ny, 0, 0.0f, 0, FALSE, FALSE, 0);
    if (!down || !up) { PLog(@"[%@] 事件创建失败", tag); return; }
    pDispatch(client, down);
    [NSThread sleepForTimeInterval:0.08];
    pDispatch(client, up);
    PLog(@"[%@] 已派发点击 (%.0f,%.0f) → 归一化 (%.4f,%.4f)", tag, pt.x, pt.y, nx, ny);
}

// 防重入：一次只跑一个策略（后台线程 sleep 出 80ms 按压间隔）
static void phTapStrategy(int strategy, CGPoint pt) {
    int expected = 0;
    if (!atomic_compare_exchange_strong(&g_busy, &expected, 1)) {
        PLog(@"[策略%d] 上一次点击还没跑完，跳过", strategy);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            IOHIDEventSystemClientRef c = NULL;
            NSString *tag = nil;
            @try {
                if (strategy == 0) {
                    if (!g_c0 && pCreate) g_c0 = pCreate(CFAllocatorGetDefault());
                    c = g_c0; tag = @"策略A:Create";
                } else if (strategy == 1) {
                    if (!g_c1 && pCreateWithType) g_c1 = pCreateWithType(CFAllocatorGetDefault(), 0, NULL);
                    c = g_c1; tag = @"策略B:CreateWithType(0)";
                } else {
                    if (!g_c2 && pCreateWithType) g_c2 = pCreateWithType(CFAllocatorGetDefault(), 1, NULL);
                    c = g_c2; tag = @"策略C:CreateWithType(1)";
                }
            } @catch (NSException *e) { PLog(@"[策略%d] client 创建异常: %@", strategy, e); }
            phTapWithClient(c, pt, tag ?: @"策略?");
        } @finally { atomic_store(&g_busy, 0); }
    });
}

// ---------------- 悬浮球 + 面板（复用哨兵已验证的窗口/面板结构） ----------------
static UIWindow *g_ballWin = nil;
static UIWindow *g_panelWin = nil;
static UITextView *g_panelLog = nil;
static UILabel *g_panelState = nil;
static CGPoint g_ballCenter = CGPointMake(26, 187);   // 左侧球中心（点击自证目标）

static void phCreateBall(void) {
    if (g_ballWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] &&
            sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
    }
    if (!scene) { PLog(@"ball: no scene"); return; }
    CGSize S = scene.screen.bounds.size;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(6, S.height * 0.19, 40, 40);
    w.windowLevel = UIWindowLevelAlert + 90;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    g_ballWin = w;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = w.bounds;
    b.layer.cornerRadius = 20;
    b.backgroundColor = [UIColor colorWithRed:0.10 green:0.30 blue:0.28 alpha:0.55];
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    b.clipsToBounds = YES;
    [b setTitle:@"幻" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [b addTarget:[PhantomActions class] action:@selector(onBallTap)
 forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:b];

    w.hidden = NO;
    PLog(@"phantom ball created at (%.0f, %.0f) 中心=(%.0f, %.0f)",
         w.frame.origin.x, w.frame.origin.y, w.center.x, w.center.y);
    g_ballCenter = w.center;
}

// ---------------- 验证序列 ----------------
static void phRunVerification(void) {
    PLog(@"========== 触摸合成验证开始 ==========");
    PLog(@"验证方法：三次合成点击幻影悬浮球中心 (%.0f, %.0f)，哪个策略把球点开（面板弹出）哪个就有效",
         g_ballCenter.x, g_ballCenter.y);
    PLog(@"如果你看到面板自己弹出来 = 对应策略的合成触摸真的能驱动 UI");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        phShowBanner(@"幻影：策略A 点击悬浮球…");
        phTapStrategy(0, g_ballCenter);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        phShowBanner(@"幻影：策略B 点击悬浮球…");
        phTapStrategy(1, g_ballCenter);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(13 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        phShowBanner(@"幻影：策略C 点击悬浮球…");
        phTapStrategy(2, g_ballCenter);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(17 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        phShowBanner(@"幻影：验证完成，点球看日志");
        PLog(@"========== 触摸合成验证结束（哪个策略点开了面板，日志里看面板状态） ==========");
    });
}

// ---------------- 极简横幅（复用哨兵结构） ----------------
static UIWindow *g_bannerWin = nil;
static UILabel *g_bannerLabel = nil;

static void phShowBanner(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindowScene *scene = nil;
            for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]] &&
                    sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
            }
            if (!scene) return;
            CGSize scr = scene.screen.bounds.size;
            CGFloat sbH = 44;
            if (@available(iOS 13.0, *)) sbH = scene.statusBarManager.statusBarFrame.size.height;
            if (sbH < 20) sbH = 44;
            CGFloat h = 40, y = sbH + 6;
            if (!g_bannerWin) {
                UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
                w.windowLevel = UIWindowLevelAlert + 88;
                w.backgroundColor = [UIColor colorWithRed:0.08 green:0.42 blue:0.36 alpha:0.94];
                w.clipsToBounds = YES;
                UILabel *lb = [[UILabel alloc] initWithFrame:CGRectZero];
                lb.textAlignment = NSTextAlignmentCenter;
                lb.font = [UIFont boldSystemFontOfSize:14];
                lb.textColor = [UIColor whiteColor];
                lb.numberOfLines = 1;
                lb.adjustsFontSizeToFitWidth = YES;
                lb.minimumScaleFactor = 0.7;
                g_bannerLabel = lb;
                [w addSubview:lb];
                g_bannerWin = w;
            }
            g_bannerWin.frame = CGRectMake(0, y - h, scr.width, h);
            g_bannerLabel.frame = g_bannerWin.bounds;
            g_bannerLabel.text = text;
            g_bannerWin.hidden = NO;
            [UIView animateWithDuration:0.22 animations:^{
                g_bannerWin.frame = CGRectMake(0, y, scr.width, h);
            }];
            static int gen = 0;
            int my = ++gen;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (my != gen || !g_bannerWin) return;
                [UIView animateWithDuration:0.25 animations:^{
                    g_bannerWin.frame = CGRectMake(0, y - h, scr.width, h);
                } completion:^(BOOL f) { if (my == gen && g_bannerWin) g_bannerWin.hidden = YES; }];
            });
        } @catch (NSException *e) { PLog(@"banner exception: %@", e); }
    });
}

// ---------------- 面板（日志视图 + 复制日志 + 重新验证） ----------------
static void phShowPanel(void);
static void phRunVerification(void);

@interface PhantomActions : NSObject
@end
@implementation PhantomActions
+ (void)onBallTap { phShowPanel(); }
+ (void)onCopy { 
    NSString *log = [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil];
    [UIPasteboard generalPasteboard].string = log ?: @"(日志为空)";
}
+ (void)onRerun {
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_panelWin setHidden:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ phRunVerification(); });
}
@end

static void phShowPanel(void) {
    @try {
        if (g_panelWin) {
            // 已开就刷新日志
            NSString *log = [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil];
            g_panelLog.text = log ?: @"(日志为空)";
            NSIndexPath *dummy = nil; (void)dummy;
            [g_panelLog scrollRangeToVisible:NSMakeRange(g_panelLog.text.length, 0)];
            return;
        }
        UIWindowScene *scene = nil;
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] &&
                sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
        }
        if (!scene) { PLog(@"panel: no scene"); return; }
        CGSize S = scene.screen.bounds.size;

        UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
        w.frame = CGRectMake(0, 0, S.width, S.height);
        w.windowLevel = UIWindowLevelAlert + 95;
        w.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        w.userInteractionEnabled = YES;
        g_panelWin = w;

        UIControl *mask = [[UIControl alloc] initWithFrame:w.bounds];
        [mask addTarget:[PhantomActions class] action:@selector(onPanelClose)
      forControlEvents:UIControlEventTouchUpInside];
        [w addSubview:mask];

        CGFloat pw = round(S.width * 0.86);
        CGFloat ph = S.height * 0.62;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake((S.width - pw) / 2.0, (S.height - ph) / 2.0, pw, ph)];
        card.backgroundColor = [UIColor colorWithRed:0.173 green:0.173 blue:0.180 alpha:0.96];
        card.layer.cornerRadius = 16;
        card.clipsToBounds = YES;
        [w addSubview:card];

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, pw - 32, 22)];
        t.text = [NSString stringWithFormat:@"幻影 v%@ · 触摸合成验证", PH_VERSION];
        t.font = [UIFont boldSystemFontOfSize:16];
        t.textColor = [UIColor whiteColor];
        [card addSubview:t];

        UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(16, 40, pw - 32, 18)];
        st.font = [UIFont systemFontOfSize:12];
        st.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        st.text = [NSString stringWithFormat:@"IOKit=%@ · hook0=%d hook1=%d hook2=%d",
                   g_iokitReady ? @"就绪" : @"不可用",
                   g_c0 != NULL, g_c1 != NULL, g_c2 != NULL];
        [card addSubview:st];
        g_panelState = st;

        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(12, 64, pw - 24, ph - 64 - 60)];
        tv.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: [UIFont systemFontOfSize:10.5];
        tv.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        tv.layer.cornerRadius = 8;
        tv.editable = NO;
        NSString *log = [NSString stringWithContentsOfFile:g_logPath encoding:NSUTF8StringEncoding error:nil];
        tv.text = log ?: @"(日志为空)";
        [tv scrollRangeToVisible:NSMakeRange(tv.text.length, 0)];
        [card addSubview:tv];
        g_panelLog = tv;

        CGFloat bw = (pw - 14 * 2 - 10) / 2.0;
        UIButton *copy = [UIButton buttonWithType:UIButtonTypeCustom];
        copy.frame = CGRectMake(14, ph - 16 - 40, bw, 40);
        copy.backgroundColor = [UIColor colorWithRed:0.227 green:0.227 blue:0.235 alpha:1.0];
        copy.layer.cornerRadius = 10;
        [copy setTitle:@"📋 复制日志" forState:UIControlStateNormal];
        copy.titleLabel.font = [UIFont systemFontOfSize:14];
        [copy addTarget:[PhantomActions class] action:@selector(onCopy)
       forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:copy];

        UIButton *rerun = [UIButton buttonWithType:UIButtonTypeCustom];
        rerun.frame = CGRectMake(14 + bw + 10, ph - 16 - 40, bw, 40);
        rerun.backgroundColor = [UIColor whiteColor];
        rerun.layer.cornerRadius = 10;
        [rerun setTitle:@"▶ 重新验证" forState:UIControlStateNormal];
        rerun.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [rerun addTarget:[PhantomActions class] action:@selector(onRerun)
       forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:rerun];

        w.hidden = NO;
        PLog(@"panel shown");
    } @catch (NSException *e) { PLog(@"panel exception: %@", e); }
}

@implementation PhantomActions (Panel)
+ (void)onPanelClose {
    if (g_panelWin) { g_panelWin.hidden = YES; g_panelWin = nil; g_panelLog = nil; }
}
@end

// ---------------- 自测（模拟器 e2e） ----------------
static int g_stPass = 0, g_stFail = 0;
static NSMutableString *g_stLog = nil;
#define PH_CHECK(cond, name) do { \
    if (cond) { g_stPass++; stWrite([NSString stringWithFormat:@"PASS %@", (name)]); } \
    else { g_stFail++; stWrite([NSString stringWithFormat:@"FAIL %@", (name)]); } \
} while (0)
static void stWrite(NSString *line) {
    PLog(@"selftest: %@", line);
    if (!g_stLog) g_stLog = [NSMutableString string];
    [g_stLog appendFormat:@"%@\n", line];
}

static void phSelftest(void) {
    if (g_stLog) return;
    g_stLog = [NSMutableString string];
    PLog(@"selftest begin");

    PH_CHECK(g_iokitReady == NO, @"模拟器无真实 IOKit → 优雅降级（不崩）");
    PH_CHECK(g_ballWin != nil, @"悬浮球窗口已创建");
    phShowPanel();
    PH_CHECK(g_panelWin != nil && !g_panelWin.hidden, @"验证面板已显示");
    PH_CHECK(g_panelLog != nil && g_panelLog.text.length > 0, @"面板日志视图有内容");

    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [g_stLog writeToFile:[doc stringByAppendingPathComponent:@"Phantom_selftest.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    PLog(@"selftest RESULT pass=%d fail=%d", g_stPass, g_stFail);
    stWrite([NSString stringWithFormat:@"RESULT pass=%d fail=%d", g_stPass, g_stFail]);
}

// ---------------- 入口 ----------------
__attribute__((constructor))
static void phantom_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        PLog(@"Phantom v%@ 注入加载（触摸合成验证版）", PH_VERSION);
        g_iokitReady = phLoadIOKit();

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL selftest = [ud boolForKey:@"phantom_selftest"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            phCreateBall();
            if (selftest) { phSelftest(); return; }
            if (!g_iokitReady) {
                phShowBanner(@"幻影：此环境无 IOKit 真实符号（模拟器？），点球看日志");
                return;
            }
            phRunVerification();
        });
    });
}
