// 幻影 Phantom —— 脚本管理（多脚本：保存 / 加载 / 重命名 / 删除 / 分享）
// 存法复用动作模型的 toDict/fromDict，落盘到 Documents/scripts/<名字>.json

#import "PH.h"

static NSString *phScriptDir(void) {
    NSString *d = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                   stringByAppendingPathComponent:@"scripts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

NSString *PHScriptPath(NSString *name) {
    return [[phScriptDir() stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"json"];
}

NSArray<NSString *> *PHScriptList(void) {
    NSArray<NSString *> *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:phScriptDir() error:nil];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *f in all) {
        if ([f.pathExtension isEqualToString:@"json"]) [out addObject:[f stringByDeletingPathExtension]];
    }
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

BOOL PHScriptSave(NSString *name) {
    if (!name.length) return NO;
    NSMutableArray *arr = [NSMutableArray array];
    for (PHAction *a in PHActions()) [arr addObject:[a toDict]];
    NSData *d = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
    if (!d) { PHLogLine(@"脚本保存失败：序列化出错"); return NO; }
    BOOL ok = [d writeToFile:PHScriptPath(name) atomically:YES];
    PHLogLine([NSString stringWithFormat:@"脚本%@：%@（%lu 个动作）", ok ? @"已保存" : @"保存失败",
               name, (unsigned long)arr.count]);
    return ok;
}

BOOL PHScriptLoad(NSString *name) {
    NSData *d = [NSData dataWithContentsOfFile:PHScriptPath(name)];
    if (!d) { PHLogLine([NSString stringWithFormat:@"脚本加载失败：找不到 %@", name]); return NO; }
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![arr isKindOfClass:[NSArray class]]) { PHLogLine(@"脚本加载失败：文件格式不对"); return NO; }
    [PHActions() removeAllObjects];
    for (NSDictionary *dd in arr) {
        if ([dd isKindOfClass:[NSDictionary class]]) [PHActions() addObject:[PHAction fromDict:dd]];
    }
    PHSaveTasks();
    PHLogLine([NSString stringWithFormat:@"脚本已加载：%@（%lu 个动作）", name, (unsigned long)PHActions().count]);
    return YES;
}

BOOL PHScriptDelete(NSString *name) {
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:PHScriptPath(name) error:nil];
    PHLogLine([NSString stringWithFormat:@"脚本%@：%@", ok ? @"已删除" : @"删除失败", name]);
    return ok;
}

BOOL PHScriptRename(NSString *from, NSString *to) {
    if (!from.length || !to.length) return NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PHScriptPath(to)]) {
        PHLogLine([NSString stringWithFormat:@"重命名失败：%@ 已存在", to]);
        return NO;
    }
    BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:PHScriptPath(from)
                                                     toPath:PHScriptPath(to) error:nil];
    PHLogLine([NSString stringWithFormat:@"脚本%@：%@ → %@", ok ? @"已重命名" : @"重命名失败", from, to]);
    return ok;
}

void PHScriptShare(NSString *name) {
    NSString *path = PHScriptPath(name);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { PHToast(@"脚本不存在"); return; }
    UIViewController *root = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.rootViewController && w.windowLevel < UIWindowLevelAlert) { root = w.rootViewController; break; }
    }
    if (!root) { PHToast(@"拿不到界面，无法分享"); return; }
    UIActivityViewController *av = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [root presentViewController:av animated:YES completion:nil];
    });
}
