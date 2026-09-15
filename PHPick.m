// 幻影 Phantom —— 屏幕选点器（点选坐标 / 拖框选区）
// 约束：悬浮窗里 UIGestureRecognizer 不触发（老坑）→ 一律用 UIControl 触摸通路
// 坐标一律存「屏幕像素点」，面板直接显示，执行器直接用

#import "PH.h"

static UIWindow *g_pkWin    = nil;
static UIView   *g_pkRect   = nil;    // 区域模式下的选框
static UILabel  *g_pkRead   = nil;    // 坐标读数
static UILabel  *g_pkHint   = nil;    // 顶部提示
static CGPoint   g_pkStart  = {0, 0};
static NSInteger g_pkIndex  = -1;
static BOOL      g_pkForB   = NO;
static BOOL      g_pkRegion = NO;

@interface PHPickActions : NSObject
+ (void)onCancel;
@end

@interface PHPickOverlay : UIControl
- (void)phRead:(CGPoint)p;
@end

static void phPickClose(void) {
    if (g_pkWin) { g_pkWin.hidden = YES; g_pkWin = nil; }
    g_pkRect = nil; g_pkRead = nil; g_pkHint = nil;
}

static void phPickFinish(CGPoint a, CGPoint b) {
    NSMutableArray<PHAction *> *acts = PHActions();
    NSInteger idx = g_pkIndex;
    BOOL forB = g_pkForB, region = g_pkRegion;
    phPickClose();
    if (idx < 0 || idx >= (NSInteger)acts.count) { PHToast(@"动作已不存在"); return; }
    PHAction *act = [acts objectAtIndex:(NSUInteger)idx];
    if (region) {
        act.regionText = [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", a.x, a.y, b.x, b.y];
        PHLogLine([NSString stringWithFormat:@"选区已设置：%@ → (%.0f,%.0f) %.0fx%.0f",
                   [PHAction typeName:act.type], a.x, a.y, b.x, b.y]);
        PHToast([NSString stringWithFormat:@"区域 %.0f,%.0f %.0fx%.0f", a.x, a.y, b.x, b.y]);
    } else if (forB) {
        act.pointB = a; act.hasPointB = YES;
        PHLogLine([NSString stringWithFormat:@"终点已设置：(%.0f, %.0f)", a.x, a.y]);
        PHToast([NSString stringWithFormat:@"终点 %.0f, %.0f", a.x, a.y]);
    } else {
        act.pointA = a; act.hasPointA = YES;
        PHLogLine([NSString stringWithFormat:@"坐标已设置：(%.0f, %.0f)", a.x, a.y]);
        PHToast([NSString stringWithFormat:@"坐标 %.0f, %.0f", a.x, a.y]);
    }
    PHSaveTasks();
    PHShowActionEdit(idx);          // 回到编辑面板，直接看到结果
}

@implementation PHPickOverlay

- (void)phRead:(CGPoint)p {
    g_pkRead.text = [NSString stringWithFormat:@"%.0f, %.0f", p.x, p.y];
    CGSize S = self.bounds.size;
    if (g_pkRegion) {
        CGFloat w = fabs(p.x - g_pkStart.x), h = fabs(p.y - g_pkStart.y);
        g_pkHint.text = [NSString stringWithFormat:@"松开确定：%.0f×%.0f", w, h];
    } else {
        g_pkHint.text = [NSString stringWithFormat:@"%@：松开确定　归一化 %.3f, %.3f",
                         g_pkForB ? @"滑动终点" : @"点击位置",
                         S.width > 0 ? p.x / S.width : 0, S.height > 0 ? p.y / S.height : 0];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    g_pkStart = [t locationInView:self];
    if (g_pkRegion) {
        g_pkRect.hidden = NO;
        g_pkRect.frame = CGRectMake(g_pkStart.x, g_pkStart.y, 0.0, 0.0);
    }
    [self phRead:g_pkStart];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    CGPoint p = [t locationInView:self];
    if (g_pkRegion) {
        g_pkRect.frame = CGRectMake(MIN(g_pkStart.x, p.x), MIN(g_pkStart.y, p.y),
                                    fabs(p.x - g_pkStart.x), fabs(p.y - g_pkStart.y));
    }
    [self phRead:p];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    CGPoint p = [t locationInView:self];
    if (g_pkRegion) {
        CGFloat w = fabs(p.x - g_pkStart.x), h = fabs(p.y - g_pkStart.y);
        if (w < 12 || h < 12) {                    // 手一抖就松手 → 不算，让人重拖
            g_pkHint.text = @"区域太小了，重新拖一次（至少 12×12）";
            g_pkRect.hidden = YES;
            return;
        }
        phPickFinish(CGPointMake(MIN(g_pkStart.x, p.x), MIN(g_pkStart.y, p.y)), CGPointMake(w, h));
    } else {
        phPickFinish(p, CGPointZero);
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    g_pkRect.hidden = YES;
}

@end

@implementation PHPickActions
+ (void)onCancel {
    phPickClose();
    PHToast(@"已取消");
}
@end

void PHShowPointPicker(NSInteger actionIndex, BOOL forPointB, BOOL regionMode) {
    if (PHIsPanelOpen()) PHCloseAllPanels();      // 收起面板，露出要选的那一层屏幕
    if (g_pkWin) phPickClose();
    UIWindowScene *scene = PHBestScene();
    if (!scene) { PHToast(@"拿不到屏幕，无法选点"); return; }
    CGSize S = scene.screen.bounds.size;

    g_pkIndex = actionIndex; g_pkForB = forPointB; g_pkRegion = regionMode;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, S.width, S.height);
    w.windowLevel = UIWindowLevelAlert + 96;
    w.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    g_pkWin = w;

    PHPickOverlay *ov = [[PHPickOverlay alloc] initWithFrame:w.bounds];
    ov.backgroundColor = [UIColor clearColor];
    [w addSubview:ov];

    UILabel *hint = PHLabel(@"", 13, [UIColor whiteColor], YES);
    hint.textAlignment = NSTextAlignmentCenter;
    hint.backgroundColor = [UIColor colorWithRed:0.08 green:0.42 blue:0.36 alpha:0.94];
    hint.frame = CGRectMake(0, 0, S.width, 40);
    [w addSubview:hint];
    g_pkHint = hint;

    UILabel *rd = PHLabel(@"", 26, [UIColor whiteColor], YES);
    rd.textAlignment = NSTextAlignmentCenter;
    rd.layer.shadowColor = [UIColor blackColor].CGColor;
    rd.layer.shadowOpacity = 0.7;
    rd.layer.shadowRadius = 4;
    rd.frame = CGRectMake(0, S.height / 2.0 - 24, S.width, 36);
    [w addSubview:rd];
    g_pkRead = rd;

    UIView *rect = [[UIView alloc] init];
    rect.backgroundColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.65 alpha:0.22];
    rect.layer.borderColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.65 alpha:0.9].CGColor;
    rect.layer.borderWidth = 1.0;
    rect.hidden = YES;
    [w addSubview:rect];
    g_pkRect = rect;

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake((S.width - 120) / 2.0, S.height - 96, 120, 42);
    cancel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    cancel.layer.cornerRadius = 21;
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    [cancel setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [cancel addTarget:[PHPickActions class] action:@selector(onCancel)
     forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:cancel];

    hint.text = regionMode ? @"拖动框选识别区域，松手确定"
                           : @"点一下屏幕选位置（拖到位再松手也行）";
    w.hidden = NO;
    PHLogLine([NSString stringWithFormat:@"选点器打开：%@（动作 #%ld）",
               regionMode ? @"区域" : (forPointB ? @"终点" : @"坐标"), (long)actionIndex]);
}
