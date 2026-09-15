// 幻影 Phantom —— 识别引擎（截屏 / 识字 / 识色 / 识图）
// 识字：Vision OCR（参数复用哨兵已验证的那套）
// 识色：区域平均色比对
// 识图：Vision 图像特征距离（平台自带，不手写模板匹配）

#import "PH.h"
#import <Vision/Vision.h>

static NSString *phDocs(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

#pragma mark - 截屏（跳过我方浮层）

UIImage *PHCaptureScreen(void) {
    __block UIImage *img = nil;
    void (^work)(void) = ^{
        @try {
            UIWindowScene *scene = PHBestScene();
            if (!scene) return;
            NSArray<UIWindow *> *wins = [scene.windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
                return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
            }];
            CGSize pts = scene.screen.bounds.size;
            if (pts.width < 2 || pts.height < 2) return;
            UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
            fmt.scale = scene.screen.scale;
            fmt.opaque = NO;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:pts format:fmt];
            img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
                for (UIWindow *w in wins) {
                    if (w.windowLevel >= UIWindowLevelAlert + 80) continue;   // 我方浮层（球/面板/提示/选点），不拍进去
                    if (w.hidden || w.alpha < 0.01 || w.frame.size.width < 1) continue;
                    [w drawViewHierarchyInRect:w.frame afterScreenUpdates:NO];
                }
            }];
        } @catch (NSException *e) {
            PHLogLine([NSString stringWithFormat:@"截屏异常：%@", e.reason]);
        }
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return img;
}

// 按「屏幕点」坐标裁剪（选点器存的就是点坐标）
UIImage *PHCropRegionPts(UIImage *full, CGRect rPts) {
    if (!full || !full.CGImage) return nil;
    CGImageRef cg = full.CGImage;
    size_t W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
    CGFloat scale = full.size.width > 0 ? ((CGFloat)W / full.size.width) : 1.0;
    CGFloat x0 = rPts.origin.x * scale, y0 = rPts.origin.y * scale;
    CGFloat w = rPts.size.width * scale, h = rPts.size.height * scale;
    if (x0 < 0) { w += x0; x0 = 0; }
    if (y0 < 0) { h += y0; y0 = 0; }
    if (x0 + w > W) w = W - x0;
    if (y0 + h > H) h = H - y0;
    if (w < 4 || h < 4) return nil;
    CGImageRef sub = CGImageCreateWithImageInRect(cg, CGRectMake(floor(x0), floor(y0), floor(w), floor(h)));
    if (!sub) return nil;
    UIImage *out = [UIImage imageWithCGImage:sub scale:full.scale orientation:full.imageOrientation];
    CGImageRelease(sub);
    return out;
}

// regionText "x,y,w,h"（点坐标）；空 = 全屏
static CGRect phRegionFromConfig(NSString *t) {
    UIWindowScene *scene = PHBestScene();
    CGSize S = scene ? scene.screen.bounds.size : CGSizeMake(390, 844);
    if (!t.length) return CGRectMake(0, 0, S.width, S.height);
    NSArray<NSString *> *p = [t componentsSeparatedByString:@","];
    if (p.count < 4) return CGRectMake(0, 0, S.width, S.height);
    return CGRectMake([p[0] doubleValue], [p[1] doubleValue], [p[2] doubleValue], [p[3] doubleValue]);
}

#pragma mark - 识字（Vision OCR）

static NSString *phNorm(NSString *s) {
    NSMutableString *m = [NSMutableString string];
    NSCharacterSet *skip = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ([skip characterIsMember:c]) continue;
        [m appendString:[[NSString stringWithCharacters:&c length:1] lowercaseString]];
    }
    return m;
}

// 同步返回识别到的文本行
static NSArray<NSString *> *phOCR(UIImage *img) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (!img || !img.CGImage) return out;
    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc]
        initWithCompletionHandler:^(VNRequest *request, NSError *reqErr) {
            if (reqErr) PHLogLine([NSString stringWithFormat:@"OCR 错误：%@", reqErr.localizedDescription]);
            for (VNObservation *o in (request.results ?: @[])) {
                if (![o isKindOfClass:[VNRecognizedTextObservation class]]) continue;
                VNRecognizedText *t = [((VNRecognizedTextObservation *)o) topCandidates:1].firstObject;
                if (!t || !t.string.length) continue;
                if (t.confidence < 0.30f) continue;
                [out addObject:phNorm(t.string)];
            }
        }];
    req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    req.recognitionLanguages = @[@"zh-Hans", @"en-US"];
    req.usesLanguageCorrection = NO;      // 认关键字，别让系统"纠"掉
    req.minimumTextHeight = 0.0f;
    @try {
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:img.CGImage options:@{}];
        [h performRequests:@[req] error:nil];
    } @catch (NSException *e) {
        PHLogLine([NSString stringWithFormat:@"OCR 异常：%@", e.reason]);
    }
    return out;
}

#pragma mark - 识色

// 把区域缩到 1×1 绘制 = 平均色（CoreGraphics 自带缩放，不手写像素遍历）
static UIColor *phAvgColor(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return nil;
    unsigned char px[4] = {0, 0, 0, 0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), cg);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    return [UIColor colorWithRed:px[0] / 255.0 green:px[1] / 255.0 blue:px[2] / 255.0 alpha:1.0];
}

static NSString *phHex(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return @"?";
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

static UIColor *phColorFromHex(NSString *s) {
    NSString *t = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                   stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (t.length != 6) return nil;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:t] scanHexInt:&v]) return nil;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0 alpha:1.0];
}

// 识色核心判定（抽出来便于单测）：返回是否命中，并带出最近距离与对应色值
BOOL PHColorHitInImage(UIImage *img, NSArray<NSString *> *colors, double similarity,
                       double *outDist, NSString **outHex) {
    UIColor *avg = phAvgColor(img);
    if (!avg || !colors.count) return NO;
    CGFloat r1 = 0, g1 = 0, b1 = 0;
    [avg getRed:&r1 green:&g1 blue:&b1 alpha:NULL];
    double best = 9.0, thr = (1.0 - similarity) + 0.05;
    NSString *bestHex = @"?";
    for (NSString *hx in colors) {
        UIColor *want = phColorFromHex(hx);
        if (!want) continue;
        CGFloat r2 = 0, g2 = 0, b2 = 0;
        [want getRed:&r2 green:&g2 blue:&b2 alpha:NULL];
        double d = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2)) / sqrt(3.0);
        if (d < best) { best = d; bestHex = hx; }
    }
    if (outDist) *outDist = best;
    if (outHex) *outHex = bestHex;
    return best <= thr;
}

// 取屏幕上某点（4×4 平均）的颜色
NSString *PHColorHexAtPoint(CGPoint pt) {
    UIImage *shot = PHCaptureScreen();
    UIImage *one = PHCropRegionPts(shot, CGRectMake(pt.x - 2, pt.y - 2, 4, 4));
    if (!one) return nil;
    UIColor *c = phAvgColor(one);
    return c ? phHex(c) : nil;
}

#pragma mark - 识图（Vision 特征距离）

static VNFeaturePrintObservation *phFeature(UIImage *img) {
    if (!img || !img.CGImage) return nil;
    VNGenerateImageFeaturePrintRequest *req = [[VNGenerateImageFeaturePrintRequest alloc] init];
    @try {
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:img.CGImage options:@{}];
        [h performRequests:@[req] error:nil];
    } @catch (NSException *e) { return nil; }
    VNFeaturePrintObservation *o = req.results.firstObject;
    return [o isKindOfClass:[VNFeaturePrintObservation class]] ? o : nil;
}

static UIImage *phLoadTemplate(NSString *name) {
    if (!name.length) return nil;
    NSString *p = [phDocs() stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) return nil;
    return [UIImage imageWithContentsOfFile:p];
}

#pragma mark - 对外：识别一个动作

BOOL PHRecognizeAction(PHAction *a) {
    if (!a) return NO;
    CGRect region = phRegionFromConfig(a.regionText);
    UIImage *shot = PHCaptureScreen();
    if (!shot) { PHLogLine(@"  识别失败：截屏拿不到画面"); return NO; }
    UIImage *crop = PHCropRegionPts(shot, region);
    if (!crop) { PHLogLine(@"  识别失败：区域无效（先用区域选择器框一下）"); return NO; }

    if (a.type == PHActionTypeText) {
        NSArray<NSString *> *lines = phOCR(crop);
        NSMutableString *shown = [NSMutableString string];
        for (NSUInteger i = 0; i < lines.count && i < 8; i++) [shown appendFormat:@"%@ ", lines[i]];
        if (!a.textList.count) { PHLogLine(@"  识字：没有配关键词，跳过"); return NO; }
        for (NSString *want in a.textList) {
            NSString *w = phNorm(want);
            if (!w.length) continue;
            for (NSString *l in lines) {
                if ([l containsString:w]) {
                    PHLogLine([NSString stringWithFormat:@"  识字命中「%@」（区域内文本：%@）", want, shown]);
                    return YES;
                }
            }
        }
        PHLogLine([NSString stringWithFormat:@"  识字未命中（区域内文本：%@）", shown.length ? shown : @"（没认到字）"]);
        return NO;
    }

    if (a.type == PHActionTypeColor) {
        if (!a.colorList.count) { PHLogLine(@"  识色：没有配颜色，跳过"); return NO; }
        double best = 9.0, thr = 0;
        NSString *bestHex = @"?";
        BOOL hit = PHColorHitInImage(crop, a.colorList, a.similarity, &best, &bestHex);
        UIColor *avg = phAvgColor(crop);
        thr = (1.0 - a.similarity) + 0.05;
        PHLogLine([NSString stringWithFormat:@"  识色：实测 %@，最接近 %@ 距离 %.3f（阈值 %.3f）→ %@",
                   phHex(avg), bestHex, best, thr, hit ? @"命中" : @"未命中"]);
        return hit;
    }

    if (a.type == PHActionTypeImage) {
        if (!a.imageList.count) { PHLogLine(@"  识图：还没选模板图，跳过"); return NO; }
        VNFeaturePrintObservation *cf = phFeature(crop);
        if (!cf) { PHLogLine(@"  识图：取特征失败"); return NO; }
        double thr = (1.0 - a.similarity) * 2.0;      // 相似度 0.9 → 距离阈值 0.20
        for (NSString *name in a.imageList) {
            UIImage *tpl = phLoadTemplate(name);
            if (!tpl) { PHLogLine([NSString stringWithFormat:@"  识图：模板 %@ 找不到", name]); continue; }
            VNFeaturePrintObservation *tf = phFeature(tpl);
            if (!tf) continue;
            double d = 0;
            NSError *err = nil;
            if ([cf computeDistance:&d toFeaturePrint:tf error:&err]) {
                PHLogLine([NSString stringWithFormat:@"  识图 %@：距离 %.3f（阈值 %.2f）%@",
                           name, d, thr, d <= thr ? @"→ 命中" : @""]);
                if (d <= thr) return YES;
            } else if (err) {
                PHLogLine([NSString stringWithFormat:@"  识图比对出错：%@", err.localizedDescription]);
            }
        }
        return NO;
    }

    return NO;
}

#pragma mark - 相册选模板图（识图用）

static id g_tplPicker = nil;

@interface PHTplPicker : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic) NSInteger idx;
@end

@implementation PHTplPicker
- (void)imagePickerController:(UIImagePickerController *)p didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [p dismissViewControllerAnimated:YES completion:nil];
    NSInteger idx = self.idx;
    if (!img || idx < 0 || idx >= (NSInteger)PHActions().count) return;
    NSString *name = [NSString stringWithFormat:@"tpl_%.0f.png", [[NSDate date] timeIntervalSince1970]];
    NSString *path = [phDocs() stringByAppendingPathComponent:name];
    if (![UIImagePNGRepresentation(img) writeToFile:path atomically:YES]) { PHToast(@"模板图保存失败"); return; }
    PHAction *a = [PHActions() objectAtIndex:(NSUInteger)idx];
    [a.imageList addObject:name];
    PHSaveTasks();
    PHLogLine([NSString stringWithFormat:@"识图模板已保存：%@", name]);
    PHToast(@"模板图已添加");
    PHShowActionEdit(idx);
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)p {
    [p dismissViewControllerAnimated:YES completion:nil];
}
@end

void PHShowTemplatePicker(NSInteger actionIndex) {
    UIWindowScene *scene = PHBestScene();
    UIViewController *root = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.windowScene == scene && w.rootViewController && w.windowLevel < UIWindowLevelAlert) {
            root = w.rootViewController; break;
        }
    }
    if (!root) { for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w.rootViewController) { root = w.rootViewController; break; } } }
    if (!root) { PHToast(@"拿不到界面，无法打开相册"); return; }
    if (PHIsPanelOpen()) PHCloseAllPanels();
    PHTplPicker *pk = [[PHTplPicker alloc] init];
    pk.idx = actionIndex;
    g_tplPicker = pk;
    UIImagePickerController *ip = [[UIImagePickerController alloc] init];
    ip.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    ip.delegate = pk;
    dispatch_async(dispatch_get_main_queue(), ^{
        [root presentViewController:ip animated:YES completion:nil];
    });
}
