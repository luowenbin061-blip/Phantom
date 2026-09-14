// 幻影 Phantom —— 动作模型 + 任务列表
// 字段设计照老贝贝的界面文案（动作描述/执行次数/每次动作等待时间(毫秒)/各动作专属参数）

#import "PH.h"

@implementation PHAction

+ (instancetype)actionWithType:(PHActionType)type {
    PHAction *a = [[PHAction alloc] init];
    a.type = type;
    a.times = 1;
    a.waitAfterMs = 0;
    a.desc = @"";
    a.pressMs = 30;
    a.intervalMs = 100;
    a.swipeSteps = 10;
    a.swipeMs = 300;
    a.similarity = 0.9;
    a.waitMs = 1000;
    a.replayScale = 1.0;
    a.textList = [NSMutableArray array];
    a.imageList = [NSMutableArray array];
    a.colorList = [NSMutableArray array];
    a.recordEvents = [NSMutableArray array];
    a.successActions = [NSMutableArray array];
    switch (type) {
        case PHActionTypeClick:       a.desc = @"点击屏幕一次"; break;
        case PHActionTypeDoubleClick: a.desc = @"点击屏幕两次"; break;
        case PHActionTypeLongPress:   a.desc = @"按住屏幕一会"; break;
        case PHActionTypeSwipe:       a.desc = @"从A点滑动到B点"; break;
        case PHActionTypeImage:       a.desc = @"识别图片内容并操作"; break;
        case PHActionTypeColor:       a.desc = @"识别颜色内容并操作"; break;
        case PHActionTypeText:        a.desc = @"识别文字内容并操作"; break;
        case PHActionTypeWait:        a.desc = @"等待一段时间"; break;
        case PHActionTypeRecord:      a.desc = @"录制触摸并回放"; break;
    }
    return a;
}

+ (NSString *)typeName:(PHActionType)type {
    switch (type) {
        case PHActionTypeClick:       return @"点击";
        case PHActionTypeDoubleClick: return @"双击";
        case PHActionTypeLongPress:   return @"长按";
        case PHActionTypeSwipe:       return @"滑动";
        case PHActionTypeImage:       return @"识图";
        case PHActionTypeColor:       return @"识色";
        case PHActionTypeText:        return @"识字";
        case PHActionTypeWait:        return @"等待";
        case PHActionTypeRecord:      return @"录制";
    }
    return @"未知";
}

+ (NSString *)typeDesc:(PHActionType)type {
    switch (type) {
        case PHActionTypeClick:       return @"点击屏幕一次";
        case PHActionTypeDoubleClick: return @"点击屏幕两次";
        case PHActionTypeLongPress:   return @"按住屏幕一会";
        case PHActionTypeSwipe:       return @"从A点滑动到B点";
        case PHActionTypeImage:       return @"识别图片内容并操作";
        case PHActionTypeColor:       return @"识别颜色内容并操作";
        case PHActionTypeText:        return @"识别文字内容并操作";
        case PHActionTypeWait:        return @"等待一段时间";
        case PHActionTypeRecord:      return @"录制触摸并回放";
    }
    return @"";
}

+ (NSString *)typeSymbol:(PHActionType)type {
    switch (type) {
        case PHActionTypeClick:       return @"hand.tap";
        case PHActionTypeDoubleClick: return @"hand.tap.fill";
        case PHActionTypeLongPress:   return @"hand.point.up.left";
        case PHActionTypeSwipe:       return @"hand.draw";
        case PHActionTypeImage:       return @"photo";
        case PHActionTypeColor:       return @"drop";
        case PHActionTypeText:        return @"textformat";
        case PHActionTypeWait:        return @"clock";
        case PHActionTypeRecord:      return @"record.circle";
    }
    return @"questionmark";
}

- (NSString *)summary {
    switch (self.type) {
        case PHActionTypeClick:
            return self.hasPointA ? [NSString stringWithFormat:@"(%.0f,%.0f) 按下%.0fms",
                                     self.pointA.x, self.pointA.y, self.pressMs] : @"未设置坐标";
        case PHActionTypeDoubleClick:
            return self.hasPointA ? [NSString stringWithFormat:@"(%.0f,%.0f) 间隔%.0fms",
                                     self.pointA.x, self.pointA.y, self.intervalMs] : @"未设置坐标";
        case PHActionTypeLongPress:
            return self.hasPointA ? [NSString stringWithFormat:@"(%.0f,%.0f) 按住%.0fms",
                                     self.pointA.x, self.pointA.y, self.pressMs] : @"未设置坐标";
        case PHActionTypeSwipe:
            if (!self.hasPointA || !self.hasPointB) return @"未设置滑动轨迹";
            return [NSString stringWithFormat:@"(%.0f,%.0f)→(%.0f,%.0f) %ld步/%.0fms",
                    self.pointA.x, self.pointA.y, self.pointB.x, self.pointB.y,
                    (long)self.swipeSteps, self.swipeMs];
        case PHActionTypeImage:
            return [NSString stringWithFormat:@"%lu 张图 · 相似度 %.2f",
                    (unsigned long)self.imageList.count, self.similarity];
        case PHActionTypeColor:
            return [NSString stringWithFormat:@"%lu 个色块 · 相似度 %.2f",
                    (unsigned long)self.colorList.count, self.similarity];
        case PHActionTypeText:
            return self.textList.count ? [self.textList componentsJoinedByString:@","]
                                       : @"未设置识别文本";
        case PHActionTypeWait:
            return [NSString stringWithFormat:@"等待 %.0fms", self.waitMs];
        case PHActionTypeRecord:
            return [NSString stringWithFormat:@"%lu 个事件 · %.1f倍",
                    (unsigned long)self.recordEvents.count, self.replayScale];
    }
    return @"";
}

- (NSDictionary *)toDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"type"] = @(self.type);
    d[@"desc"] = self.desc ?: @"";
    d[@"times"] = @(self.times);
    d[@"waitAfterMs"] = @(self.waitAfterMs);
    d[@"pointA"] = @[@(self.pointA.x), @(self.pointA.y)];
    d[@"pointB"] = @[@(self.pointB.x), @(self.pointB.y)];
    d[@"hasPointA"] = @(self.hasPointA);
    d[@"hasPointB"] = @(self.hasPointB);
    d[@"pressMs"] = @(self.pressMs);
    d[@"intervalMs"] = @(self.intervalMs);
    d[@"swipeSteps"] = @(self.swipeSteps);
    d[@"swipeMs"] = @(self.swipeMs);
    d[@"regionText"] = self.regionText ?: @"";
    d[@"similarity"] = @(self.similarity);
    d[@"textList"] = self.textList ?: @[];
    d[@"imageList"] = self.imageList ?: @[];
    d[@"colorList"] = self.colorList ?: @[];
    d[@"waitMs"] = @(self.waitMs);
    d[@"recordEvents"] = self.recordEvents ?: @[];
    d[@"replayScale"] = @(self.replayScale);
    NSMutableArray *sub = [NSMutableArray array];
    for (PHAction *a in self.successActions) [sub addObject:[a toDict]];
    d[@"successActions"] = sub;
    return d;
}

+ (instancetype)fromDict:(NSDictionary *)d {
    PHAction *a = [PHAction actionWithType:[d[@"type"] integerValue]];
    if (d[@"desc"]) a.desc = d[@"desc"];
    if (d[@"times"]) a.times = [d[@"times"] integerValue];
    if (d[@"waitAfterMs"]) a.waitAfterMs = [d[@"waitAfterMs"] doubleValue];
    NSArray *pa = d[@"pointA"], *pb = d[@"pointB"];
    if (pa.count == 2) a.pointA = CGPointMake([pa[0] doubleValue], [pa[1] doubleValue]);
    if (pb.count == 2) a.pointB = CGPointMake([pb[0] doubleValue], [pb[1] doubleValue]);
    a.hasPointA = [d[@"hasPointA"] boolValue];
    a.hasPointB = [d[@"hasPointB"] boolValue];
    if (d[@"pressMs"]) a.pressMs = [d[@"pressMs"] doubleValue];
    if (d[@"intervalMs"]) a.intervalMs = [d[@"intervalMs"] doubleValue];
    if (d[@"swipeSteps"]) a.swipeSteps = [d[@"swipeSteps"] integerValue];
    if (d[@"swipeMs"]) a.swipeMs = [d[@"swipeMs"] doubleValue];
    if (d[@"regionText"]) a.regionText = d[@"regionText"];
    if (d[@"similarity"]) a.similarity = [d[@"similarity"] doubleValue];
    if ([d[@"textList"] isKindOfClass:[NSArray class]]) a.textList = [d[@"textList"] mutableCopy];
    if ([d[@"imageList"] isKindOfClass:[NSArray class]]) a.imageList = [d[@"imageList"] mutableCopy];
    if ([d[@"colorList"] isKindOfClass:[NSArray class]]) a.colorList = [d[@"colorList"] mutableCopy];
    if (d[@"waitMs"]) a.waitMs = [d[@"waitMs"] doubleValue];
    if ([d[@"recordEvents"] isKindOfClass:[NSArray class]]) a.recordEvents = [d[@"recordEvents"] mutableCopy];
    if (d[@"replayScale"]) a.replayScale = [d[@"replayScale"] doubleValue];
    if ([d[@"successActions"] isKindOfClass:[NSArray class]]) {
        a.successActions = [NSMutableArray array];
        for (NSDictionary *sd in d[@"successActions"]) [a.successActions addObject:[PHAction fromDict:sd]];
    }
    return a;
}

@end

#pragma mark - 全局任务列表 + 持久化

static NSMutableArray<PHAction *> *g_actions = nil;

static NSString *PHTaskFile(void) {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [(doc ?: NSHomeDirectory()) stringByAppendingPathComponent:@"phantom_tasks.json"];
}

NSMutableArray<PHAction *> *PHActions(void) {
    if (!g_actions) {
        g_actions = [NSMutableArray array];
        NSData *data = [NSData dataWithContentsOfFile:PHTaskFile()];
        if (data) {
            NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([arr isKindOfClass:[NSArray class]]) {
                for (NSDictionary *d in arr) {
                    if ([d isKindOfClass:[NSDictionary class]]) [g_actions addObject:[PHAction fromDict:d]];
                }
            }
        }
    }
    return g_actions;
}

void PHSaveTasks(void) {
    NSMutableArray *arr = [NSMutableArray array];
    for (PHAction *a in PHActions()) [arr addObject:[a toDict]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
    if (data) [data writeToFile:PHTaskFile() atomically:YES];
}
