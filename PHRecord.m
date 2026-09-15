// 幻影 Phantom —— 录制（捕获真实触摸）
// 手法：替换 UIApplication 的 sendEvent: 实现，原实现照常转发（App 行为不变）
// 只记「按下 / 抬起」两类点 + 相对时间；回放在 PHExec.m 里做

#import "PH.h"
#import <objc/runtime.h>

static IMP           g_origSendEvent = NULL;
static BOOL          g_recording = NO;
static BOOL          g_recSwizzled = NO;
static NSMutableArray<NSDictionary *> *g_recBuf = nil;
static NSTimeInterval g_recStart = 0;

static void phSendEvent(id self, SEL _cmd, UIEvent *ev) {
    if (g_recording && ev && ev.type == UIEventTypeTouches && g_recBuf) {
        for (UITouch *t in ev.allTouches) {
            if (t.phase == UITouchPhaseBegan || t.phase == UITouchPhaseEnded) {
                CGPoint p = [t locationInView:nil];       // 屏幕坐标
                [g_recBuf addObject:@{
                    @"t": @([[NSDate date] timeIntervalSince1970] - g_recStart),
                    @"x": @(p.x),
                    @"y": @(p.y),
                    @"p": @(t.phase == UITouchPhaseBegan ? 1 : 2)
                }];
            }
        }
    }
    if (g_origSendEvent) ((void (*)(id, SEL, UIEvent *))g_origSendEvent)(self, _cmd, ev);
}

static void phEnsureSwizzle(void) {
    if (g_recSwizzled) return;
    Method m = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
    if (!m) { PHLogLine(@"录制钩子安装失败：找不到 sendEvent:"); return; }
    g_origSendEvent = method_getImplementation(m);
    method_setImplementation(m, (IMP)phSendEvent);
    g_recSwizzled = YES;
    PHLogLine(@"录制钩子已安装（UIApplication sendEvent:）");
}

void PHRecordStart(void) {
    phEnsureSwizzle();
    if (!g_recBuf) g_recBuf = [NSMutableArray array];
    [g_recBuf removeAllObjects];
    g_recStart = [[NSDate date] timeIntervalSince1970];
    g_recording = YES;
    PHLogLine(@"录制开始：现在操作屏幕，点「停止录制」结束");
}

NSArray<NSDictionary *> *PHRecordStop(void) {
    g_recording = NO;
    NSArray *out = g_recBuf ? [g_recBuf copy] : @[];
    PHLogLine([NSString stringWithFormat:@"录制结束：抓到 %lu 个触摸点", (unsigned long)out.count]);
    return out;
}

BOOL PHIsRecording(void) { return g_recording; }
NSInteger PHRecordCount(void) { return g_recBuf ? (NSInteger)g_recBuf.count : 0; }
