// 幻影 Phantom —— 全部面板 UI
// 结构照老贝贝：展开面板（任务列表+按钮）→ 添加动作卡片（9 项）→ 各动作编辑卡片
//                → 设置弹窗（分区）→ 脚本管理弹窗 → 输入卡片

#import "PH.h"

#pragma mark - 前向声明

PHAction *PHActs(void);   // 当前正在编辑的动作

#pragma mark - 面板容器（单窗口复用）

static UIWindow     *g_pWin = nil;
static UIView       *g_pCard = nil;
static UIScrollView *g_pScroll = nil;
static CGFloat       g_pW = 0;      // 卡片内宽
static CGFloat       g_pY = 0;      // 内容累计 y
static BOOL          g_pTall = NO;  // 是否强制高面板

// 主菜单（照老贝贝主界面）独立窗口
static UIWindow     *g_mWin = nil;
static UIView       *g_mCard = nil;
static UIScrollView *g_mScroll = nil;
static UIView       *g_mListHost = nil;
static CGFloat       g_mW = 0;

static void PHClosePanel(void) {
    if (g_pWin) { g_pWin.hidden = YES; g_pWin = nil; g_pCard = nil; g_pScroll = nil; }
}

BOOL PHIsPanelOpen(void) {
    return ((g_pWin != nil && !g_pWin.hidden) || (g_mWin != nil && !g_mWin.hidden));
}

@interface PHActions2 : NSObject
@end

@implementation PHActions2
+ (void)onClose { PHClosePanel(); }
@end

// 建面板：wRatio 宽比，tall=高面板
static void PHPanelBegin(NSString *title, CGFloat wRatio, BOOL tall) {
    PHClosePanel();
    g_pTall = tall;
                UIWindowScene *scene = PHBestScene();
    if (!scene) return;
    CGSize S = scene.screen.bounds.size;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, S.width, S.height);
    w.windowLevel = UIWindowLevelAlert + 95;
    w.backgroundColor = [UIColor clearColor];     // 不压暗底层（老贝贝就是不遮的）
    w.userInteractionEnabled = YES;
    g_pWin = w;

    UIControl *mask = [[UIControl alloc] initWithFrame:w.bounds];
    [mask addTarget:[PHActions2 class] action:@selector(onClose)
   forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:mask];

    CGFloat pw = round(S.width * (wRatio > 0 ? wRatio : PH_PANEL_W_RATIO));
    CGFloat ph = tall ? S.height * 0.70 : 0;   // 0 = 先占位，之后按内容算
    UIView *card = PHCardView(CGRectMake((S.width - pw) / 2.0, 0, pw, ph ? ph : 200));
    [w addSubview:card];
    g_pCard = card;
    g_pW = pw - 32;

    UILabel *t = PHLabel(title, 17, PH_TEXT, YES);
    t.frame = CGRectMake(16, 0, pw - 16 - 52, PH_TITLE_H);
    [card addSubview:t];
    UIButton *cl = PHCloseButton(32);
    cl.frame = CGRectMake(pw - 32 - 12, 9, 32, 32);
    [cl addTarget:[PHActions2 class] action:@selector(onClose)
 forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cl];
    [card addSubview:PHHairline(pw, PH_TITLE_H)];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(16, PH_TITLE_H + 12, g_pW, 200)];
    sv.showsVerticalScrollIndicator = YES;                       // 让用户看得出能滚
    sv.alwaysBounceVertical = YES;                              // 内容不满也能拖动
    sv.delaysContentTouches = NO;                               // 子按钮点击跟手，且不挡滚动
    sv.canCancelContentTouches = YES;
    sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    sv.clipsToBounds = YES;
    [card addSubview:sv];
    g_pScroll = sv;
    g_pY = 0;
    w.hidden = NO;
}

static void PHPanelSection(NSString *title) {
    if (!g_pScroll) return;
    g_pY += (g_pY > 0 ? 18 : 4);
    UILabel *l = PHLabel(title, 13, PH_DIM, NO);
    l.frame = CGRectMake(0, g_pY, g_pW, 18);
    [g_pScroll addSubview:l];
    g_pY += 24;
}

static void PHPanelAdd(UIView *v, CGFloat gap) {
    if (!g_pScroll || !v) return;
    g_pY += gap;
    CGRect f = v.frame;
    v.frame = CGRectMake(0, g_pY, g_pW, f.size.height);
    [g_pScroll addSubview:v];
    g_pY += f.size.height;
}

static void PHPanelNote(NSString *text) {
    if (!g_pScroll) return;
    g_pY += 6;
    UILabel *l = PHLabel(text, 12, PH_DIM, NO);
    l.frame = CGRectMake(0, g_pY, g_pW, 16);
    [g_pScroll addSubview:l];
    g_pY += 20;
}

// 底部按钮（1~3 个横排）
static void PHPanelButtons(NSArray<UIButton *> *btns) {
    if (!g_pCard || !btns.count) return;
    CGFloat n = btns.count;
    CGFloat gap = 10;
    CGFloat bw = (g_pW - gap * (n - 1)) / n;
    CGFloat by = 12 + g_pY + 12;
    CGFloat x = 16;
    for (UIButton *b in btns) {
        b.frame = CGRectMake(x, by, bw, PH_ROW_H);
        [g_pCard addSubview:b];
        x += bw + gap;
    }
    g_pY = by + PH_ROW_H;

    // 内容总高（不含底部按钮区）
    CGFloat contentH = MAX(0.0, g_pY - 12 - PH_ROW_H - 12);
    CGFloat ph = 12 + g_pY + 16;
    CGFloat maxH = g_pWin.bounds.size.height * 0.74;
    CGFloat scrollH = contentH;
    if (ph > maxH) {                       // 太高 → 夹住面板，滚动区吃掉差额（保底 130）
        scrollH = MAX(130.0, contentH - (ph - maxH));
        ph = maxH;
    }
    CGRect cf = g_pCard.frame;
    g_pCard.frame = CGRectMake(cf.origin.x, (g_pWin.bounds.size.height - ph) / 2.0, cf.size.width, ph);
    // 滚动区占满「标题栏之下、底部按钮之上」的全部空间：手指落在卡片里就能滚
    CGFloat availH = ph - (PH_TITLE_H + 12) - (PH_ROW_H + 24);
    g_pScroll.frame = CGRectMake(16, PH_TITLE_H + 12, g_pW, MAX(scrollH, availH));
    g_pScroll.contentSize = CGSizeMake(g_pW, contentH);
    g_pScroll.alwaysBounceVertical = YES;
}

#pragma mark - 输入卡片（改数值/文本，立即生效）

static UIWindow *g_iWin = nil;

@interface PHInputActions : NSObject
+ (void)onCancel;
+ (void)onOK;
@end

static NSString *g_iTitle = nil;
static UITextField *g_iField = nil;
static void (^g_iOK)(NSString *) = nil;

@implementation PHInputActions
+ (void)onCancel {
    if (g_iWin) { g_iWin.hidden = YES; g_iWin = nil; g_iField = nil; g_iOK = nil; }
}
+ (void)onOK {
    NSString *txt = g_iField.text ?: @"";
    void (^cb)(NSString *) = g_iOK;
    [PHInputActions onCancel];
    if (cb) cb(txt);
}
@end

static void PHInputCard(NSString *title, NSString *hint, NSString *current, void (^onOK)(NSString *)) {
    if (g_iWin) { g_iWin.hidden = YES; g_iWin = nil; }
                UIWindowScene *scene = PHBestScene();
    if (!scene) return;
    CGSize S = scene.screen.bounds.size;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, S.width, S.height);
    w.windowLevel = UIWindowLevelAlert + 101;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    g_iWin = w;

    UIControl *mask = [[UIControl alloc] initWithFrame:w.bounds];
    [mask addTarget:[PHInputActions class] action:@selector(onCancel)
   forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:mask];

    CGFloat cw = round(S.width * 0.72);
    CGFloat ch = 196;
    UIView *card = PHCardView(CGRectMake((S.width - cw) / 2.0, S.height * 0.17, cw, ch));
    [w addSubview:card];

    UILabel *t = PHLabel(title, 17, PH_TEXT, YES);
    t.frame = CGRectMake(16, 14, cw - 16 - 52, 24);
    [card addSubview:t];
    UIButton *cl = PHCloseButton(32);
    cl.frame = CGRectMake(cw - 32 - 12, 10, 32, 32);
    [cl addTarget:[PHInputActions class] action:@selector(onCancel)
 forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cl];

    UILabel *h = PHLabel(hint, 12, PH_DIM, NO);
    h.frame = CGRectMake(16, 44, cw - 32, 16);
    [card addSubview:h];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(14, 68, cw - 28, 44)];
    tf.text = current ?: @"";
    tf.textColor = PH_TEXT;
    tf.font = [UIFont systemFontOfSize:15];
    tf.backgroundColor = PH_FIELD;
    tf.layer.cornerRadius = 10;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.clearButtonMode = UITextFieldViewModeAlways;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    tf.leftView = pad;
    tf.leftViewMode = UITextFieldViewModeAlways;
    [card addSubview:tf];
    g_iField = tf;

    CGFloat bw = (cw - 14 * 2 - 10) / 2.0;
    UIButton *cancel = PHFootButton(@"取消", NO, bw);
    cancel.frame = CGRectMake(14, 128, bw, 44);
    [cancel addTarget:[PHInputActions class] action:@selector(onCancel)
      forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cancel];
    UIButton *ok = PHFootButton(@"确定", YES, bw);
    ok.frame = CGRectMake(14 + bw + 10, 128, bw, 44);
    [ok addTarget:[PHInputActions class] action:@selector(onOK)
  forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:ok];

    g_iOK = onOK;
    [w makeKeyAndVisible];            // 输入卡片必须 key，否则键盘不弹
    [tf becomeFirstResponder];
}

#pragma mark - 顶部轻提示

static UIWindow *g_tWin = nil;
void PHToast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
                        UIWindowScene *scene = PHBestScene();
            if (!scene) return;
            CGSize scr = scene.screen.bounds.size;
            CGFloat sbH = 44;
            if (@available(iOS 13.0, *)) sbH = scene.statusBarManager.statusBarFrame.size.height;
            if (sbH < 20) sbH = 44;
            CGFloat h = 40, y = sbH + 6;
            if (!g_tWin) {
                UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
                w.windowLevel = UIWindowLevelAlert + 99;
                w.backgroundColor = [UIColor colorWithRed:0.08 green:0.42 blue:0.36 alpha:0.94];
                w.clipsToBounds = YES;
                UILabel *lb = PHLabel(@"", 14, [UIColor whiteColor], YES);
                lb.textAlignment = NSTextAlignmentCenter;
                lb.tag = 9001;
                [w addSubview:lb];
                g_tWin = w;
            }
            UILabel *lb = [g_tWin viewWithTag:9001];
            g_tWin.frame = CGRectMake(0, y - h, scr.width, h);
            lb.frame = g_tWin.bounds;
            lb.text = text;
            g_tWin.hidden = NO;
            [UIView animateWithDuration:0.2 animations:^{ g_tWin.frame = CGRectMake(0, y, scr.width, h); }];
            static int gen = 0;
            int my = ++gen;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (my != gen || !g_tWin) return;
                [UIView animateWithDuration:0.22 animations:^{
                    g_tWin.frame = CGRectMake(0, y - h, scr.width, h);
                } completion:^(BOOL f) { if (my == gen && g_tWin) g_tWin.hidden = YES; }];
            });
        } @catch (NSException *e) { }
    });
}

#pragma mark - 主菜单（照老贝贝主界面：标题 + 动作卡片列表 + 底部四个彩色圆按钮）

@interface PHMenuActions : NSObject
+ (void)onClose;
+ (void)onAdd;
+ (void)onDel;
+ (void)onSet;
+ (void)onRun;
+ (void)onCard:(UIButton *)b;
+ (void)onDelCard:(UIButton *)b;
@end

void PHCloseMenu(void) {
    if (g_mWin) { g_mWin.hidden = YES; g_mWin = nil; g_mCard = nil; g_mScroll = nil; g_mListHost = nil; }
    PHBallNotifyActivity();      // 关面板也算一次操作（重排 20 秒收纳计时）
}

// 一张动作小卡片
static UIButton *PHActionCard(PHAction *a, NSInteger idx, CGFloat w, BOOL deleteMode) {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.frame = CGRectMake(0, 0, w, 46);
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];   // 半透明，透出毛玻璃
    card.layer.cornerRadius = 10;
    card.tag = idx;
    [card addTarget:[PHMenuActions class]
             action:(deleteMode ? @selector(onDelCard:) : @selector(onCard:))
   forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [[UIImageView alloc] initWithImage:PHIcon([PHAction typeSymbol:a.type], 16, PH_ACCENT)];
    icon.frame = CGRectMake(11, 15, 17, 17);
    icon.userInteractionEnabled = NO;
    [card addSubview:icon];

    UILabel *n = PHLabel([NSString stringWithFormat:@"%ld. %@", (long)(idx + 1), [PHAction typeName:a.type]], 14, PH_TEXT, YES);
    n.frame = CGRectMake(36, 6, w - 36 - 40, 18);
    n.userInteractionEnabled = NO;
    [card addSubview:n];

    UILabel *sm = PHLabel(a.summary, 11, PH_DIM, NO);
    sm.frame = CGRectMake(36, 24, w - 36 - 40, 14);
    sm.lineBreakMode = NSLineBreakByTruncatingTail;
    sm.userInteractionEnabled = NO;
    [card addSubview:sm];

    UIImageView *tail = [[UIImageView alloc] initWithImage:PHIcon(deleteMode ? @"minus.circle.fill" : @"chevron.right",
                                                                  15, deleteMode ? PH_BTN_DEL : PH_FAINT)];
    tail.frame = CGRectMake(w - 28, 16, 15, 15);
    tail.userInteractionEnabled = NO;
    [card addSubview:tail];
    return card;
}

static void PHBuildMenuList(BOOL deleteMode) {
    if (!g_mListHost) return;
    for (UIView *v in g_mListHost.subviews) [v removeFromSuperview];
    CGFloat w = g_mW;
    NSMutableArray<PHAction *> *list = PHActions();
    CGFloat h = 0;
    if (!list.count) {
        UILabel *l = PHLabel(@"还没有动作\n点下方蓝色 ＋ 添加", 13, PH_DIM, NO);
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 2;
        l.frame = CGRectMake(0, 26, w, 50);
        [g_mListHost addSubview:l];
        h = 100;
    } else {
        NSInteger i = 0;
        for (PHAction *a in list) {
            UIButton *card = PHActionCard(a, i, w, deleteMode);
            card.frame = CGRectMake(0, h, w, 46);
            [g_mListHost addSubview:card];
            h += 52;
            i++;
        }
        h = MAX(h, 124);
    }
    CGRect f = g_mListHost.frame;
    g_mListHost.frame = CGRectMake(f.origin.x, f.origin.y, w, h);
    if (g_mScroll) g_mScroll.contentSize = CGSizeMake(w, h);
}

static void PHBuildMenuWindow(BOOL deleteMode) {
    PHCloseMenu();
    PHClosePanel();
                UIWindowScene *scene = PHBestScene();
    if (!scene) return;
    CGSize S = scene.screen.bounds.size;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = CGRectMake(0, 0, S.width, S.height);
    w.windowLevel = UIWindowLevelAlert + 95;
    w.backgroundColor = [UIColor colorWithWhite:0 alpha:0.30];
    w.userInteractionEnabled = YES;
    g_mWin = w;

    UIControl *mask = [[UIControl alloc] initWithFrame:w.bounds];
    [mask addTarget:[PHMenuActions class] action:@selector(onClose)
   forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:mask];

    CGFloat pw = round(S.width * 0.60);
    CGFloat hdrH = 46, barH = 64;
    CGFloat listMax = S.height * 0.62;
    (void)listMax;
    // 先按内容估高，再定最大
    CGFloat contentH = 0;
    if (PHActions().count) contentH = PHActions().count * 54;
    else contentH = 108;
    CGFloat listH = MIN(contentH, S.height * 0.34);
    CGFloat ph = hdrH + listH + barH;

    UIView *card = PHCardView(CGRectMake((S.width - pw) / 2.0, (S.height - ph) / 2.0, pw, ph));
    [w addSubview:card];
    g_mCard = card;
    g_mW = pw - 24;

    // 标题（青色）+ 右上白色圆 ✕
    UILabel *t = PHLabel([NSString stringWithFormat:@"幻影 Phantom v%@", PH_VERSION], 16, PH_TITLE_GREEN, YES);
    t.frame = CGRectMake(18, 0, pw - 18 - 52, hdrH);
    [card addSubview:t];
    UIButton *cl = PHCloseButton(30);
    cl.frame = CGRectMake(pw - 30 - 14, (hdrH - 30) / 2.0, 30, 30);
    [cl addTarget:[PHMenuActions class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cl];
    [card addSubview:PHHairline(pw, hdrH)];

    // 动作卡片列表
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(12, hdrH + 12, g_mW, listH - 12)];
    sv.showsVerticalScrollIndicator = NO;
    [card addSubview:sv];
    g_mScroll = sv;
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, g_mW, contentH)];
    [sv addSubview:host];
    g_mListHost = host;

    // 底部按钮栏（深灰条 + 四个彩色圆按钮）
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, ph - barH, pw, barH)];
    bar.backgroundColor = PH_BAR;
    [card addSubview:bar];

    CGFloat bsz = 42;
    CGFloat gap = (pw - 4 * bsz) / 5.0;
    NSArray *symbols = @[ @"plus", @"minus", @"ellipsis",
                          (PHIsRunning() ? @"stop.fill" : @"play.fill") ];
    NSArray *colors  = @[ PH_BTN_ADD, PH_BTN_DEL, PH_BTN_SET, PH_BTN_RUN ];
    NSArray *sels    = @[ @"onAdd", @"onDel", @"onSet", @"onRun" ];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = PHCircleButton(symbols[i], colors[i], bsz);
        b.frame = CGRectMake(gap * (i + 1) + bsz * i, (barH - bsz) / 2.0, bsz, bsz);
        [b addTarget:[PHMenuActions class] action:NSSelectorFromString(sels[i])
    forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:b];
    }

    PHBuildMenuList(deleteMode);
    w.hidden = NO;
}

@implementation PHMenuActions
+ (void)onClose    { PHCloseMenu(); }
+ (void)onAdd      { PHShowAddAction(); }
+ (void)onDel      { PHBuildMenuWindow(YES); PHToast(@"点动作卡片即删除"); }
+ (void)onSet      { PHShowSettings(); }
+ (void)onRun {
    if (PHIsRunning()) { PHStopTask(); PHToast(@"正在停止…"); PHRefreshMenuIfVisible(); return; }
    if (!PHActions().count) { PHToast(@"先点蓝色 ＋ 添加动作"); return; }
    PHRunTask();
    PHRefreshMenuIfVisible();
}
+ (void)onCard:(UIButton *)b    { PHShowActionEdit(b.tag); }
+ (void)onDelCard:(UIButton *)b {
    NSInteger i = b.tag;
    if (i >= 0 && i < (NSInteger)[PHActions() count]) {
        NSString *name = [PHAction typeName:[PHActions() objectAtIndex:(NSUInteger)i].type];
        [PHActions() removeObjectAtIndex:(NSUInteger)i];
        PHSaveTasks();
        PHToast([NSString stringWithFormat:@"已删除：%@", name]);
    }
    PHBuildMenuWindow(YES);
}
@end

void PHShowMenu(void) {
    PHBallNotifyActivity();                  // 开面板算一次操作
    if (g_mWin) { PHCloseMenu(); return; }   // 再点一次收起
    PHBuildMenuWindow(NO);
}

void PHRefreshMenuIfVisible(void) {
    if (g_mWin && g_mListHost) PHBuildMenuList(NO);
}

// 判定基准：只有「主面板」打开才算悬浮球被点开（通用面板开着不算）
BOOL PHIsMainMenuOpen(void) {
    return (g_mWin != nil && !g_mWin.hidden);
}

// 自检前清场：把主面板和通用面板都关掉，露出球、排除干扰
void PHCloseAllPanels(void) {
    PHClosePanel();
    PHCloseMenu();
}

#pragma mark - 添加动作卡片（9 项）

@interface PHAddActions : NSObject
@end

@implementation PHAddActions
+ (void)onPick:(UIButton *)b { PHAddActionAndEdit((PHActionType)(b.tag - 2000)); }
@end

void PHShowAddAction(void) {
    PHPanelBegin(@"添加动作", 0.66, YES);
    CGFloat y = 0;
    for (NSInteger i = 0; i < 9; i++) {
        PHActionType t = (PHActionType)i;
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, g_pW, 48)];
        row.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        row.layer.cornerRadius = 9;

        UIImageView *icon = [[UIImageView alloc] initWithImage:PHIcon([PHAction typeSymbol:t], 17, PH_ACCENT)];
        icon.frame = CGRectMake(12, 15, 19, 19);
        [row addSubview:icon];

        UILabel *n = PHLabel([PHAction typeName:t], 14, PH_TEXT, YES);
        n.frame = CGRectMake(40, 6, g_pW - 40 - 36, 18);
        [row addSubview:n];
        UILabel *d = PHLabel([PHAction typeDesc:t], 11, PH_DIM, NO);
        d.frame = CGRectMake(40, 25, g_pW - 40 - 36, 14);
        [row addSubview:d];

        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.frame = row.bounds;
        hit.tag = 2000 + i;
        [hit addTarget:[PHAddActions class] action:@selector(onPick:)
      forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:hit];

        [g_pScroll addSubview:row];
        y += 52;
    }
    g_pY = y;
    UIButton *cancel = PHFootButton(@"取消", NO, g_pW);
    [cancel addTarget:[PHActions2 class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    PHPanelButtons(@[ cancel ]);
}

void PHAddActionAndEdit(PHActionType type) {
    PHAction *a = [PHAction actionWithType:type];
    [PHActions() addObject:a];
    PHSaveTasks();
    PHToast([NSString stringWithFormat:@"已添加：%@", [PHAction typeName:type]]);
    PHShowActionEdit(PHActions().count - 1);
}

#pragma mark - 动作编辑卡片（9 种）

@interface PHEditActions : NSObject
@end

static NSInteger g_editIndex = -1;

@implementation PHEditActions
+ (void)onDesc      { [self fieldEdit:@"动作描述" hint:@"给这个动作起个名字" key:@"desc"]; }
+ (void)onTimes     { [self numEdit:@"执行次数" hint:@"0 = 无限循环" key:@"times"]; }
+ (void)onWaitAfter { [self numEdit:@"每次动作等待时间(毫秒)" hint:@"这个动作做完后等多久" key:@"waitAfterMs"]; }
+ (void)onPress     { [self numEdit:@"按下时长(毫秒)" hint:@"按住多久才松开" key:@"pressMs"]; }
+ (void)onInterval  { [self numEdit:@"双击间隔时长(毫秒)" hint:@"两次点击之间的间隔" key:@"intervalMs"]; }
+ (void)onSteps     { [self numEdit:@"滑动步数" hint:@"滑动过程分几步" key:@"swipeSteps"]; }
+ (void)onSwipeMs   { [self numEdit:@"滑动时间(毫秒)" hint:@"整个滑动过程耗时" key:@"swipeMs"]; }
+ (void)onSimilar   { [self numEdit:@"匹配相似度(0.0~1.0)" hint:@"越高越严格" key:@"similarity"]; }
+ (void)onWaitMs    { [self numEdit:@"等待时间(毫秒)" hint:@"例：5000 = 等 5 秒" key:@"waitMs"]; }
+ (void)onScale     { [self numEdit:@"回放倍数" hint:@"2.0 = 两倍速" key:@"replayScale"]; }
+ (void)onTexts     { [self listEdit:@"识别文本列表" hint:@"多个用逗号分隔" key:@"textList"]; }
+ (void)onPointA    { PHShowPointPicker(g_editIndex, NO, NO); }
+ (void)onPointB    { PHShowPointPicker(g_editIndex, YES, NO); }
+ (void)onRegion    { PHShowPointPicker(g_editIndex, NO, YES); }
+ (void)onImages    { PHShowTemplatePicker(g_editIndex); }
+ (void)onColors    { PHShowColorPicker(g_editIndex); }
+ (void)onRecord    { PHToast(@"录制功能将在后续阶段接入"); }
+ (void)onSuccess   { PHToast(@"「识别成功后动作」将在识别引擎阶段接入"); }
+ (void)onDelete    {
    if (g_editIndex >= 0 && g_editIndex < (NSInteger)[PHActions() count]) {
        [PHActions() removeObjectAtIndex:g_editIndex];
        PHSaveTasks();
    }
    PHShowMenu();
    PHToast(@"已删除该动作");
}

+ (void)fieldEdit:(NSString *)title hint:(NSString *)hint key:(NSString *)key {
    PHAction *a = PHActs();
    if (!a) return;
    NSString *cur = [a valueForKey:key];
    PHInputCard(title, hint, cur, ^(NSString *text) {
        [a setValue:(text ?: @"") forKey:key];
        PHSaveTasks();
        PHShowActionEdit(g_editIndex);
    });
}
+ (void)numEdit:(NSString *)title hint:(NSString *)hint key:(NSString *)key {
    PHAction *a = PHActs();
    if (!a) return;
    double cur = [[a valueForKey:key] doubleValue];
    PHInputCard(title, hint, [NSString stringWithFormat:@"%.1f", cur], ^(NSString *text) {
        double v = text.doubleValue;
        if ([key isEqualToString:@"similarity"] && (v <= 0 || v > 1)) v = 0.9;
        if ([key isEqualToString:@"swipeSteps"] && v < 1) v = 1;
        if ([key isEqualToString:@"replayScale"] && v <= 0) v = 1.0;
        [a setValue:@(v) forKey:key];
        PHSaveTasks();
        PHShowActionEdit(g_editIndex);
    });
}
+ (void)listEdit:(NSString *)title hint:(NSString *)hint key:(NSString *)key {
    PHAction *a = PHActs();
    if (!a) return;
    NSArray *cur = [a valueForKey:key];
    PHInputCard(title, hint, [cur componentsJoinedByString:@","], ^(NSString *text) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *p in [text componentsSeparatedByString:@","]) {
            NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length) [out addObject:t];
        }
        [a setValue:out forKey:key];
        PHSaveTasks();
        PHShowActionEdit(g_editIndex);
    });
}
@end

// 便捷：当前编辑的动作
PHAction *PHActs(void) {
    if (g_editIndex < 0 || g_editIndex >= (NSInteger)PHActions().count) return nil;
    return [PHActions() objectAtIndex:(NSUInteger)g_editIndex];
}

void PHShowActionEdit(NSInteger index) {
    if (index < 0 || index >= (NSInteger)PHActions().count) { PHShowMenu(); return; }
    g_editIndex = index;
    PHAction *a = [PHActions() objectAtIndex:(NSUInteger)index];
    PHPanelBegin([NSString stringWithFormat:@"%@动作编辑", [PHAction typeName:a.type]], 0.68, YES);

    PHPanelSection(@"动作描述");
    PHPanelAdd(PHFieldRow(a.desc.length ? a.desc : @"点击输入动作描述", g_pW,
                          [PHEditActions class], @selector(onDesc)), 0);

    PHPanelSection(@"执行次数");
    PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%ld%@", (long)a.times, a.times == 0 ? @"（无限循环）" : @""],
                          g_pW, [PHEditActions class], @selector(onTimes)), 0);

    switch (a.type) {
        case PHActionTypeClick:
            PHPanelSection(@"点击坐标");
            PHPanelAdd(PHFieldRow(a.hasPointA ? [NSString stringWithFormat:@"%.0f, %.0f", a.pointA.x, a.pointA.y] : @"点击设置坐标",
                                  g_pW, [PHEditActions class], @selector(onPointA)), 0);
            PHPanelSection(@"点击按下时长(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.pressMs], g_pW,
                                  [PHEditActions class], @selector(onPress)), 0);
            break;
        case PHActionTypeDoubleClick:
            PHPanelSection(@"双击坐标");
            PHPanelAdd(PHFieldRow(a.hasPointA ? [NSString stringWithFormat:@"%.0f, %.0f", a.pointA.x, a.pointA.y] : @"点击设置坐标",
                                  g_pW, [PHEditActions class], @selector(onPointA)), 0);
            PHPanelSection(@"双击按下时长(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.pressMs], g_pW,
                                  [PHEditActions class], @selector(onPress)), 0);
            PHPanelSection(@"双击间隔时长(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.intervalMs], g_pW,
                                  [PHEditActions class], @selector(onInterval)), 0);
            break;
        case PHActionTypeLongPress:
            PHPanelSection(@"长按坐标");
            PHPanelAdd(PHFieldRow(a.hasPointA ? [NSString stringWithFormat:@"%.0f, %.0f", a.pointA.x, a.pointA.y] : @"点击设置坐标",
                                  g_pW, [PHEditActions class], @selector(onPointA)), 0);
            PHPanelSection(@"长按按下时长(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.pressMs], g_pW,
                                  [PHEditActions class], @selector(onPress)), 0);
            break;
        case PHActionTypeSwipe:
            PHPanelSection(@"滑动坐标");
            PHPanelAdd(PHFieldRow(a.hasPointA ? [NSString stringWithFormat:@"起点 %.0f, %.0f", a.pointA.x, a.pointA.y] : @"点击设置起点",
                                  g_pW, [PHEditActions class], @selector(onPointA)), 0);
            PHPanelAdd(PHFieldRow(a.hasPointB ? [NSString stringWithFormat:@"终点 %.0f, %.0f", a.pointB.x, a.pointB.y] : @"点击设置终点",
                                  g_pW, [PHEditActions class], @selector(onPointB)), 8);
            PHPanelSection(@"滑动步数");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%ld", (long)a.swipeSteps], g_pW,
                                  [PHEditActions class], @selector(onSteps)), 0);
            PHPanelSection(@"滑动时间(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.swipeMs], g_pW,
                                  [PHEditActions class], @selector(onSwipeMs)), 0);
            break;
        case PHActionTypeImage:
            PHPanelSection(@"识别区域");
            PHPanelAdd(PHFieldRow(a.regionText.length ? a.regionText : @"点击设置识别区域", g_pW,
                                  [PHEditActions class], @selector(onRegion)), 0);
            PHPanelSection(@"识别图像列表");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"已设置 %lu 张，点击编辑", (unsigned long)a.imageList.count],
                                  g_pW, [PHEditActions class], @selector(onImages)), 0);
            PHPanelSection(@"匹配相似度(0.0~1.0)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.2f", a.similarity], g_pW,
                                  [PHEditActions class], @selector(onSimilar)), 0);
            PHPanelSection(@"识别成功后动作");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"已设置 %lu 个，点击编辑",
                                   (unsigned long)a.successActions.count],
                                  g_pW, [PHEditActions class], @selector(onSuccess)), 0);
            break;
        case PHActionTypeColor:
            PHPanelSection(@"取色区域");
            PHPanelAdd(PHFieldRow(a.regionText.length ? a.regionText : @"点击设置取色区域", g_pW,
                                  [PHEditActions class], @selector(onRegion)), 0);
            PHPanelSection(@"色块列表");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"已选 %lu 色，点击编辑", (unsigned long)a.colorList.count],
                                  g_pW, [PHEditActions class], @selector(onColors)), 0);
            PHPanelSection(@"匹配相似度(0.0~1.0)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.2f", a.similarity], g_pW,
                                  [PHEditActions class], @selector(onSimilar)), 0);
            PHPanelSection(@"识别成功后动作");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"已设置 %lu 个，点击编辑",
                                   (unsigned long)a.successActions.count],
                                  g_pW, [PHEditActions class], @selector(onSuccess)), 0);
            break;
        case PHActionTypeText:
            PHPanelSection(@"识别区域");
            PHPanelAdd(PHFieldRow(a.regionText.length ? a.regionText : @"点击设置识别区域", g_pW,
                                  [PHEditActions class], @selector(onRegion)), 0);
            PHPanelSection(@"识别文本列表");
            PHPanelAdd(PHFieldRow(a.textList.count ? [a.textList componentsJoinedByString:@","] : @"点击添加识别文本",
                                  g_pW, [PHEditActions class], @selector(onTexts)), 0);
            PHPanelSection(@"识别成功后动作");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"已设置 %lu 个，点击编辑",
                                   (unsigned long)a.successActions.count],
                                  g_pW, [PHEditActions class], @selector(onSuccess)), 0);
            break;
        case PHActionTypeWait:
            PHPanelSection(@"等待时间(毫秒)");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.waitMs], g_pW,
                                  [PHEditActions class], @selector(onWaitMs)), 0);
            break;
        case PHActionTypeRecord:
            PHPanelSection(@"录制内容");
            PHPanelAdd(PHFieldRow(a.recordEvents.count
                                  ? [NSString stringWithFormat:@"已录制 %lu 个，点此重录", (unsigned long)a.recordEvents.count]
                                  : @"点击开始录制",
                                  g_pW, [PHEditActions class], @selector(onRecord)), 0);
            PHPanelSection(@"回放倍数");
            PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.1f 倍", a.replayScale], g_pW,
                                  [PHEditActions class], @selector(onScale)), 0);
            break;
    }

    PHPanelSection(@"每次动作等待时间(毫秒)");
    PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"%.0f", a.waitAfterMs], g_pW,
                          [PHEditActions class], @selector(onWaitAfter)), 0);
    PHPanelNote(@"提示：灰底行都能点开修改；坐标/区域/录制这类需要抓屏点的，等引擎阶段接入。");

    UIButton *del = PHFootButton(@"删除", NO, g_pW);
    [del addTarget:[PHEditActions class] action:@selector(onDelete) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done = PHFootButton(@"完成", YES, g_pW);
    [done addTarget:[PHActions2 class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    PHPanelButtons(@[ del, done ]);
}

#pragma mark - 设置弹窗

@interface PHSettingsActions : NSObject
@end

@implementation PHSettingsActions
+ (void)onTapTest  { PHTestSyntheticTap(); }
+ (void)onShowLog  { PHShowLogPanel(); }
+ (void)onLoop     { PHInputCard(@"整体执行次数", @"0 = 无限循环", [[NSUserDefaults standardUserDefaults] stringForKey:@"phantom_loop"] ?: @"1", ^(NSString *t) {
    [[NSUserDefaults standardUserDefaults] setObject:(t ?: @"1") forKey:@"phantom_loop"];
    PHShowSettings();
}); }
+ (void)onStartAt  { PHToast(@"定时启动将在执行引擎阶段接入"); }
+ (void)onStopAt   { PHToast(@"定时停止将在执行引擎阶段接入"); }
+ (void)onScripts  { PHShowScripts(); }
+ (void)onBallShape:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_ball_shape"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    PHBallApplyLayout();
    PHToast(s.selectedSegmentIndex ? @"悬浮球：圆形" : @"悬浮球：方形");
}
+ (void)onBallAttach:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_ball_attach"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    PHBallApplyLayout();
    PHToast(s.selectedSegmentIndex ? @"悬浮球：不吸附（可停在任意位置）" : @"悬浮球：吸附边缘");
}
+ (void)onEdgeHide:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_edge_hide"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    PHBallApplyLayout();
    PHToast(s.selectedSegmentIndex ? @"边缘收纳：开（球会藏一半到屏幕边）" : @"边缘收纳：关");
}
+ (void)onIcon     { PHShowIconPicker(); }
+ (void)onIconReset { PHResetBallIcon(); }
+ (void)onTrackShow:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_track_show"];
    PHToast(s.selectedSegmentIndex ? @"触摸轨迹显示：开" : @"触摸轨迹显示：关");
}
+ (void)onTrackRing:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_track_ring"];
    PHToast(s.selectedSegmentIndex ? @"圆环显示：开" : @"圆环显示：关");
}
+ (void)onSecure:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_secure"];
    PHToast(s.selectedSegmentIndex ? @"防录屏防截屏：开" : @"防录屏防截屏：关");
}
+ (void)onAds:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_ads"];
    PHToast(s.selectedSegmentIndex ? @"广告加速：开" : @"广告加速：关");
}
+ (void)onJump:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_jump"];
    PHToast(s.selectedSegmentIndex ? @"拦截浏览器跳转：开" : @"拦截浏览器跳转：关");
}
+ (void)onPopup:(UISegmentedControl *)s {
    [[NSUserDefaults standardUserDefaults] setInteger:s.selectedSegmentIndex forKey:@"phantom_popup"];
    PHToast(s.selectedSegmentIndex ? @"自动关闭系统弹出：开" : @"自动关闭系统弹出：关");
}
@end

static NSInteger PHCfgInt(NSString *key) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud objectForKey:key] == nil ? 0 : [ud integerForKey:key];
}

void PHShowSettings(void) {
    PHPanelBegin(@"设置", 0.62, YES);

    PHPanelSection(@"触摸引擎自检");
    PHPanelAdd(PHFieldRow(@"开始自检：几种方式各点一次悬浮按钮", g_pW,
                          [PHSettingsActions class], @selector(onTapTest)), 0);
    PHPanelAdd(PHFieldRow(@"查看日志（复制 / 排查用）", g_pW,
                          [PHSettingsActions class], @selector(onShowLog)), 8);
    PHPanelNote(@"自检时请先别碰屏幕。球自己弹开 = 那种方式可用；三种都没反应就把日志发我。");

    PHPanelSection(@"整体执行设置");
    PHPanelAdd(PHFieldRow([NSString stringWithFormat:@"执行次数：%@（0=无限）",
                           [[NSUserDefaults standardUserDefaults] stringForKey:@"phantom_loop"] ?: @"1"],
                          g_pW, [PHSettingsActions class], @selector(onLoop)), 0);
    PHPanelAdd(PHFieldRow(@"定时启动（到时间自动开始）", g_pW, [PHSettingsActions class], @selector(onStartAt)), 8);
    PHPanelAdd(PHFieldRow(@"定时停止（到时间自动停止）", g_pW, [PHSettingsActions class], @selector(onStopAt)), 8);

    PHPanelSection(@"脚本文件管理");
    PHPanelAdd(PHFieldRow(@"保存 / 加载 / 分享 / 重命名 / 删除", g_pW,
                          [PHSettingsActions class], @selector(onScripts)), 0);

    PHPanelSection(@"悬浮球形状");
    UISegmentedControl *shape = PHSegmented(@[ @"方形", @"圆形" ], PHCfgInt(@"phantom_ball_shape"), g_pW);
    [shape addTarget:[PHSettingsActions class] action:@selector(onBallShape:)
    forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(shape, 0);

    PHPanelSection(@"悬浮球吸附");
    UISegmentedControl *attach = PHSegmented(@[ @"吸附", @"不吸附" ], PHCfgInt(@"phantom_ball_attach"), g_pW);
    [attach addTarget:[PHSettingsActions class] action:@selector(onBallAttach:)
     forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(attach, 0);

    PHPanelSection(@"边缘收纳");
    UISegmentedControl *edge = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_edge_hide"), g_pW);
    [edge addTarget:[PHSettingsActions class] action:@selector(onEdgeHide:)
   forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(edge, 0);

    PHPanelSection(@"悬浮球图标");
    PHPanelAdd(PHFieldRow(@"设置自定义悬浮图标", g_pW, [PHSettingsActions class], @selector(onIcon)), 0);
    PHPanelAdd(PHFieldRow(@"恢复默认图标", g_pW, [PHSettingsActions class], @selector(onIconReset)), 8);
    PHPanelNote(@"提示：这个悬浮按钮可直接用手指拖动；松手后按上面的「吸附 / 边缘收纳」设置归位，位置会被记住。");

    PHPanelSection(@"触摸轨迹显示");
    UISegmentedControl *ts = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_track_show"), g_pW);
    [ts addTarget:[PHSettingsActions class] action:@selector(onTrackShow:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(ts, 0);

    PHPanelSection(@"触摸轨迹圆环");
    UISegmentedControl *tr = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_track_ring"), g_pW);
    [tr addTarget:[PHSettingsActions class] action:@selector(onTrackRing:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(tr, 0);

    PHPanelSection(@"防录屏防截屏");
    UISegmentedControl *se = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_secure"), g_pW);
    [se addTarget:[PHSettingsActions class] action:@selector(onSecure:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(se, 0);

    PHPanelSection(@"广告加速");
    UISegmentedControl *ad = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_ads"), g_pW);
    [ad addTarget:[PHSettingsActions class] action:@selector(onAds:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(ad, 0);

    PHPanelSection(@"拦截浏览器跳转");
    UISegmentedControl *jp = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_jump"), g_pW);
    [jp addTarget:[PHSettingsActions class] action:@selector(onJump:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(jp, 0);

    PHPanelSection(@"自动关闭系统弹出");
    UISegmentedControl *pp = PHSegmented(@[ @"关", @"开" ], PHCfgInt(@"phantom_popup"), g_pW);
    [pp addTarget:[PHSettingsActions class] action:@selector(onPopup:)
 forControlEvents:UIControlEventValueChanged];
    PHPanelAdd(pp, 0);

    UIButton *close = PHFootButton(@"关闭", YES, g_pW);
    [close addTarget:[PHActions2 class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    PHPanelButtons(@[ close ]);
}

#pragma mark - 脚本管理

@interface PHScriptActions : NSObject
@end

@implementation PHScriptActions
+ (void)onSave   { PHSaveTasks(); PHToast(@"已保存当前配置"); }
+ (void)onLoad   { PHToast(@"多脚本管理将在后续阶段接入（当前为单配置自动保存）"); }
+ (void)onShare  { PHToast(@"分享脚本将在后续阶段接入"); }
+ (void)onRename { PHToast(@"重命名将在后续阶段接入"); }
+ (void)onDelete { PHToast(@"删除脚本将在后续阶段接入"); }
@end

void PHShowScripts(void) {
    PHPanelBegin(@"脚本文件管理", 0.66, NO);
    PHPanelNote(@"当前为「单配置 + 自动保存」模式：退出 App 前会自动存到沙盒。");
    PHPanelSection(@"当前配置");
    PHPanelAdd(PHFieldRowPlain([NSString stringWithFormat:@"phantom_tasks.json · %lu 个动作",
                                (unsigned long)PHActions().count], g_pW), 0);
    PHPanelSection(@"操作");
    PHPanelAdd(PHFieldRow(@"保存当前配置", g_pW, [PHScriptActions class], @selector(onSave)), 0);
    PHPanelAdd(PHFieldRow(@"加载脚本", g_pW, [PHScriptActions class], @selector(onLoad)), 8);
    PHPanelAdd(PHFieldRow(@"分享脚本", g_pW, [PHScriptActions class], @selector(onShare)), 8);
    PHPanelAdd(PHFieldRow(@"重命名", g_pW, [PHScriptActions class], @selector(onRename)), 8);
    PHPanelAdd(PHFieldRow(@"删除脚本", g_pW, [PHScriptActions class], @selector(onDelete)), 8);

    UIButton *close = PHFootButton(@"关闭", YES, g_pW);
    [close addTarget:[PHActions2 class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    PHPanelButtons(@[ close ]);
}
