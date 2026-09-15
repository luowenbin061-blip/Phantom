// 幻影 Phantom —— 任务执行器
// 执行模型照老贝贝：动作序列 → 每个动作有「执行次数」→ 每个动作后有「每次动作等待」→ 整体「执行次数」(0=无限)
// 触摸发送走 Phantom.m 的引擎（PHFireTapPts）。触摸层未通时点击类动作会是空转，但流程/计数/日志都真实跑。

#import "PH.h"

static BOOL g_exRunning = NO;
static BOOL g_exStop    = NO;

BOOL PHIsRunning(void) { return g_exRunning; }
void PHStopTask(void)  { g_exStop = YES; }

// 可中断睡眠（分片检查停止标志）
static BOOL phExSleep(double ms) {
    double left = ms;
    while (left > 0 && !g_exStop) {
        double step = left > 50.0 ? 50.0 : left;
        usleep((useconds_t)(step * 1000.0));
        left -= step;
    }
    return !g_exStop;
}

static BOOL phExHasPoint(PHAction *a) {
    return (a.hasPointA && (a.pointA.x > 0 || a.pointA.y > 0));
}

static void phExClick(PHAction *a, NSString *what) {
    PHFireTapPts(a.pointA.x, a.pointA.y, 1, YES);
    phExSleep(MAX(10.0, a.pressMs));
    PHFireTapPts(a.pointA.x, a.pointA.y, 2, NO);
    PHLogLine([NSString stringWithFormat:@"  %@ (%.0f, %.0f) 按下 %.0fms",
               what, a.pointA.x, a.pointA.y, MAX(10.0, a.pressMs)]);
}

static void phExLongPress(PHAction *a) {
    PHFireTapPts(a.pointA.x, a.pointA.y, 1, YES);
    phExSleep(MAX(100.0, a.pressMs));
    PHFireTapPts(a.pointA.x, a.pointA.y, 2, NO);
    PHLogLine([NSString stringWithFormat:@"  长按 (%.0f, %.0f) 按住 %.0fms",
               a.pointA.x, a.pointA.y, MAX(100.0, a.pressMs)]);
}

static void phExSwipe(PHAction *a) {
    NSInteger n = MAX(2, a.swipeSteps);
    double dt = MAX(10.0, a.swipeMs) / (double)n;
    for (NSInteger i = 1; i <= n && !g_exStop; i++) {
        double t = (double)i / (double)n;
        double x = a.pointA.x + (a.pointB.x - a.pointA.x) * t;
        double y = a.pointA.y + (a.pointB.y - a.pointA.y) * t;
        PHFireTapPts(x, y, 1, YES);
        phExSleep(dt);
    }
    PHFireTapPts(a.pointB.x, a.pointB.y, 2, NO);
    PHLogLine([NSString stringWithFormat:@"  滑动 (%.0f, %.0f) → (%.0f, %.0f) %ld 步 %.0fms",
               a.pointA.x, a.pointA.y, a.pointB.x, a.pointB.y, (long)n, MAX(10.0, a.swipeMs)]);
}

// 执行一条动作（识别类留到识别引擎阶段）
static void phExAction(PHAction *a) {
    switch (a.type) {
        case PHActionTypeClick:
            if (!phExHasPoint(a)) { PHLogLine(@"  跳过：还没设置点击坐标"); return; }
            phExClick(a, @"点击");
            break;
        case PHActionTypeDoubleClick:
            if (!phExHasPoint(a)) { PHLogLine(@"  跳过：还没设置双击坐标"); return; }
            phExClick(a, @"双击·第1次");
            if (!phExSleep(MAX(20.0, a.intervalMs))) return;
            phExClick(a, @"双击·第2次");
            break;
        case PHActionTypeLongPress:
            if (!phExHasPoint(a)) { PHLogLine(@"  跳过：还没设置长按坐标"); return; }
            phExLongPress(a);
            break;
        case PHActionTypeSwipe:
            if (!phExHasPoint(a) || !a.hasPointB) { PHLogLine(@"  跳过：滑动需要起点和终点"); return; }
            phExSwipe(a);
            break;
        case PHActionTypeWait:
            PHLogLine([NSString stringWithFormat:@"  等待 %.0fms", a.waitMs]);
            phExSleep(MAX(0.0, a.waitMs));
            break;
        case PHActionTypeText:
            PHLogLine(@"  识字：识别引擎尚未接入（下一阶段）");
            break;
        case PHActionTypeImage:
            PHLogLine(@"  识图：识别引擎尚未接入（下一阶段）");
            break;
        case PHActionTypeColor:
            PHLogLine(@"  识色：识别引擎尚未接入（下一阶段）");
            break;
        case PHActionTypeRecord:
            PHLogLine(@"  录制回放：尚未接入（下一阶段）");
            break;
    }
}

void PHRunTask(void) {
    if (g_exRunning) { PHToast(@"任务正在运行"); return; }
    NSArray<PHAction *> *acts = [PHActions() copy];
    if (!acts.count) { PHToast(@"先点蓝色 ＋ 添加动作"); return; }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger loops = 1;
    if ([ud stringForKey:@"phantom_loop"]) loops = [[ud stringForKey:@"phantom_loop"] integerValue];
    if (loops < 0) loops = 1;

    g_exRunning = YES;
    g_exStop = NO;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        PHLogLine([NSString stringWithFormat:@"===== 任务开始：%lu 个动作，整体 %ld 次（0=无限）=====",
                   (unsigned long)acts.count, (long)loops]);
        NSInteger round = 0;
        while (!g_exStop && (loops == 0 || round < loops)) {
            round++;
            PHLogLine([NSString stringWithFormat:@"--- 第 %ld 轮 ---", (long)round]);
            for (PHAction *a in acts) {
                if (g_exStop) break;
                NSInteger n = a.times > 0 ? a.times : 1;      // 动作自身次数（0 视为 1）
                for (NSInteger i = 0; i < n && !g_exStop; i++) {
                    phExAction(a);
                }
                if (a.waitAfterMs > 0 && !phExSleep(a.waitAfterMs)) break;
            }
        }
        BOOL byStop = g_exStop;
        g_exRunning = NO;
        PHLogLine([NSString stringWithFormat:@"===== 任务结束（%ld 轮，%@）=====",
                   (long)round, byStop ? @"手动停止" : @"正常跑完"]);
        dispatch_async(dispatch_get_main_queue(), ^{
            PHToast(byStop ? @"任务已停止" : @"任务已跑完");
            PHRefreshMenuIfVisible();
        });
    });
}
