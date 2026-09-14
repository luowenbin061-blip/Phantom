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

#define PH_VERSION @"0.2"

static void PHShowLogPanel(void);

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

#pragma mark - 悬浮球

static UIWindow *g_ballWin = nil;

@interface PHBallActions : NSObject
+ (void)onTap;
+ (void)onLong;
@end

@implementation PHBallActions
+ (void)onTap  { PHShowMenu(); }
+ (void)onLong { PHShowLogPanel(); }
@end

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
    w.frame = CGRectMake(6, S.height * 0.19, 44, 44);
    w.windowLevel = UIWindowLevelAlert + 90;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    g_ballWin = w;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = w.bounds;
    b.backgroundColor = [UIColor colorWithRed:0.10 green:0.30 blue:0.28 alpha:0.60];
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    b.clipsToBounds = YES;
    [b setTitle:@"幻" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b addTarget:[PHBallActions class] action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    [b addTarget:[PHBallActions class] action:@selector(onLong)
forControlEvents:UIControlEventTouchDownRepeat];
    [w addSubview:b];
    w.hidden = NO;
    PLog(@"phantom ball created at (%.0f, %.0f)", w.frame.origin.x, w.frame.origin.y);
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

    PHAction *a = PHActions()[0];
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
        PLog(@"Phantom v%@ 注入加载（完整 UI 骨架版）", PH_VERSION);
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
