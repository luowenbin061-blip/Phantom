// 幻影 Phantom —— 公共头文件
// UI 视觉规格照老贝贝（哨兵已验证过一轮）：深色面板 + 圆角 + 分区靠间距 + 无分割线
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define PH_VERSION @"0.7"   // 幻影版本（启动完整显示/拖出即收纳/滚动修复）

#pragma mark - 主题
#define PH_BG      [UIColor colorWithRed:0.173 green:0.173 blue:0.180 alpha:0.95]   // #2C2C2E 面板底
#define PH_FIELD   [UIColor colorWithRed:0.227 green:0.227 blue:0.235 alpha:1.0]   // #3A3A3C 输入框/按钮
#define PH_TROUGH  [UIColor colorWithRed:0.110 green:0.110 blue:0.118 alpha:1.0]   // #1C1C1E 分段控件底
#define PH_TEXT    [UIColor whiteColor]
#define PH_DIM     [UIColor colorWithWhite:1.0 alpha:0.62]
#define PH_FAINT   [UIColor colorWithWhite:1.0 alpha:0.30]
#define PH_HAIR    [UIColor colorWithWhite:1.0 alpha:0.07]
#define PH_ACCENT  [UIColor colorWithRed:0.20 green:0.78 blue:0.65 alpha:1.0]       // 主色
// 主面板配色（照老贝贝主界面截图）
#define PH_TITLE_GREEN [UIColor colorWithRed:0.31 green:0.85 blue:0.76 alpha:1.0]   // 标题青绿
#define PH_BTN_ADD     [UIColor colorWithRed:0.18 green:0.49 blue:0.97 alpha:1.0]   // 蓝 +
#define PH_BTN_DEL     [UIColor colorWithRed:1.00 green:0.64 blue:0.15 alpha:1.0]   // 橙 −
#define PH_BTN_SET     [UIColor colorWithRed:0.69 green:0.36 blue:0.91 alpha:1.0]   // 紫 ···
#define PH_BTN_RUN     [UIColor colorWithRed:0.24 green:0.84 blue:0.36 alpha:1.0]   // 绿 ▶
#define PH_BAR         [UIColor colorWithRed:0.12 green:0.12 blue:0.13 alpha:1.0]   // 底部按钮栏底

extern const CGFloat PH_PANEL_RADIUS;    // 16
extern const CGFloat PH_ROW_H;           // 40
extern const CGFloat PH_TITLE_H;         // 50
extern const CGFloat PH_PANEL_W_RATIO;   // 0.62 面板宽 = 屏宽×比例

#pragma mark - 控件工厂（PHTheme.m）
UILabel *PHLabel(NSString *text, CGFloat size, UIColor *color, BOOL bold);
UIView  *PHFieldRow(NSString *value, CGFloat w, id target, SEL action);   // 灰框值行（点击触发 action）
UIView  *PHFieldRowPlain(NSString *value, CGFloat w);                     // 只读灰框行
UISegmentedControl *PHSegmented(NSArray<NSString *> *items, NSInteger sel, CGFloat w);
UIButton *PHFootButton(NSString *title, BOOL primary, CGFloat w);         // 底部按钮（主=白底黑字）
UIButton *PHCloseButton(CGFloat size);                                     // 白色实心圆 + 黑 X
UIView  *PHCardView(CGRect frame);                                         // 面板卡片
UIView  *PHHairline(CGFloat w, CGFloat y);
UIImage *PHIcon(NSString *symbolName, CGFloat size, UIColor *tint);       // SF Symbol
UIButton *PHCircleButton(NSString *symbol, UIColor *bg, CGFloat size);      // 彩色圆形图标按钮

#pragma mark - 动作模型（PHModel.m）
typedef NS_ENUM(NSInteger, PHActionType) {
    PHActionTypeClick = 0,      // 点击
    PHActionTypeDoubleClick,    // 双击
    PHActionTypeLongPress,      // 长按
    PHActionTypeSwipe,          // 滑动
    PHActionTypeImage,          // 识图
    PHActionTypeColor,          // 识色
    PHActionTypeText,           // 识字
    PHActionTypeWait,           // 等待
    PHActionTypeRecord          // 录制
};

@interface PHAction : NSObject
@property (nonatomic) PHActionType type;
@property (nonatomic, copy) NSString *desc;        // 动作描述（可编辑）
@property (nonatomic) NSInteger times;             // 执行次数
@property (nonatomic) double waitAfterMs;          // 每次动作等待(毫秒)

// 点击/双击/长按/滑动 坐标（归一化 0~1）
@property (nonatomic) CGPoint pointA;
@property (nonatomic) CGPoint pointB;
@property (nonatomic) BOOL hasPointA, hasPointB;
@property (nonatomic) double pressMs;              // 按下时长
@property (nonatomic) double intervalMs;           // 双击间隔
@property (nonatomic) NSInteger swipeSteps;        // 滑动步数
@property (nonatomic) double swipeMs;              // 滑动时间

// 识图/识色/识字
@property (nonatomic, copy) NSString *regionText;  // 识别区域描述
@property (nonatomic) double similarity;           // 匹配相似度 0~1
@property (nonatomic, strong) NSMutableArray<NSString *> *textList;   // 识字文本列表
@property (nonatomic, strong) NSMutableArray<NSString *> *imageList;  // 识图图像（文件名/描述）
@property (nonatomic, strong) NSMutableArray<NSString *> *colorList;  // 识色色块

// 等待
@property (nonatomic) double waitMs;

// 录制
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recordEvents;
@property (nonatomic) double replayScale;          // 回放倍数

// 识图/识色/识字 的「识别成功后动作」（嵌套动作列表）
@property (nonatomic, strong) NSMutableArray<PHAction *> *successActions;

+ (instancetype)actionWithType:(PHActionType)type;
+ (NSString *)typeName:(PHActionType)type;     // 点击 / 双击 / ...
+ (NSString *)typeDesc:(PHActionType)type;     // 点击屏幕一次 / ...
+ (NSString *)typeSymbol:(PHActionType)type;   // SF Symbol 名
- (NSString *)summary;                          // 面板/列表里的一行摘要
- (NSDictionary *)toDict;
+ (instancetype)fromDict:(NSDictionary *)d;
@end

#pragma mark - 全局任务列表（PHModel.m 里定义）
extern NSMutableArray<PHAction *> *PHActions(void);
void PHSaveTasks(void);

#pragma mark - 面板（PHUI.m）
void PHShowMenu(void);
void PHShowAddAction(void);
void PHAddActionAndEdit(PHActionType type);
void PHShowActionEdit(NSInteger index);
void PHShowSettings(void);
void PHShowScripts(void);
void PHToast(NSString *text);              // 顶部轻提示
void PHRefreshMenuIfVisible(void);
BOOL PHIsPanelOpen(void);          // 当前是否有面板在显示（自测用）
void PHRefreshBall(void);                      // 按当前设置重建悬浮球（形状/图标）
void PHBallApplyLayout(void);                  // 设置变更后立即应用（形状+吸附）
void PHShowIconPicker(void);                   // 打开相册选悬浮球图标
void PHResetBallIcon(void);                    // 恢复默认图标
void PHBallNotifyActivity(void);                // 通知"有操作"（展开 + 重排 20 秒收纳计时）
