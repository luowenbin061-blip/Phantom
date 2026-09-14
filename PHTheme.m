// 幻影 Phantom —— 主题与控件工厂
// 视觉规格照老贝贝（哨兵已对齐过一轮）：面板底 #2C2C2E / 圆角 18 / 宽度 = 屏宽×66%
// 字段标题 13px α0.62 / 输入框 #3A3A3C 圆角10 高44 / 分段控件底 #1C1C1E 选中=白药丸黑字
// 底部主按钮白底黑字、次按钮灰底白字 / 无分割线，靠间距分区

#import "PH.h"

const CGFloat PH_PANEL_RADIUS  = 16.0;
const CGFloat PH_ROW_H         = 40.0;
const CGFloat PH_TITLE_H       = 46.0;
const CGFloat PH_PANEL_W_RATIO = 0.62;

UILabel *PHLabel(NSString *text, CGFloat size, UIColor *color, BOOL bold) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

UIView *PHFieldRow(NSString *value, CGFloat w, id target, SEL action) {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, 0, w, PH_ROW_H);
    row.backgroundColor = PH_FIELD;
    row.layer.cornerRadius = 9;
    if (target && action) {
        [row addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }
    UILabel *v = PHLabel(value, 14, PH_TEXT, NO);
    v.frame = CGRectMake(13, 0, w - 13 - 28, PH_ROW_H);
    v.lineBreakMode = NSLineBreakByTruncatingHead;
    v.userInteractionEnabled = NO;
    [row addSubview:v];

    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chev.tintColor = PH_FAINT;
    chev.contentMode = UIViewContentModeScaleAspectFit;
    chev.frame = CGRectMake(w - 22, (PH_ROW_H - 13) / 2.0, 8, 13);
    chev.userInteractionEnabled = NO;
    [row addSubview:chev];
    return row;
}

UIView *PHFieldRowPlain(NSString *value, CGFloat w) {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, PH_ROW_H)];
    row.backgroundColor = PH_FIELD;
    row.layer.cornerRadius = 9;
    UILabel *v = PHLabel(value, 14, PH_TEXT, NO);
    v.frame = CGRectMake(14, 0, w - 28, PH_ROW_H);
    v.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addSubview:v];
    return row;
}

UISegmentedControl *PHSegmented(NSArray<NSString *> *items, NSInteger sel, CGFloat w) {
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:items];
    seg.frame = CGRectMake(0, 0, w, 40);
    seg.selectedSegmentIndex = sel;
    seg.backgroundColor = PH_TROUGH;
    seg.selectedSegmentTintColor = [UIColor whiteColor];
    NSDictionary *normal = @{ NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.80],
                              NSFontAttributeName: [UIFont systemFontOfSize:14] };
    NSDictionary *selected = @{ NSForegroundColorAttributeName: [UIColor blackColor],
                                NSFontAttributeName: [UIFont boldSystemFontOfSize:14] };
    [seg setTitleTextAttributes:normal forState:UIControlStateNormal];
    [seg setTitleTextAttributes:selected forState:UIControlStateSelected];
    return seg;
}

UIButton *PHFootButton(NSString *title, BOOL primary, CGFloat w) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, w, PH_ROW_H);
    b.backgroundColor = primary ? [UIColor whiteColor] : PH_FIELD;
    b.layer.cornerRadius = 10;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:primary ? [UIColor blackColor] : PH_TEXT forState:UIControlStateNormal];
    b.titleLabel.font = primary ? [UIFont boldSystemFontOfSize:15] : [UIFont systemFontOfSize:15];
    return b;
}

UIButton *PHCloseButton(CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, size, size);
    b.backgroundColor = [UIColor whiteColor];
    b.layer.cornerRadius = size / 2.0;
    [b setTitle:@"✕" forState:UIControlStateNormal];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:size * 0.45];
    return b;
}

// 半透明毛玻璃卡片（照老贝贝：能透出后面的界面，不遮挡主程序）
UIView *PHCardView(CGRect frame) {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = [UIColor clearColor];
    card.layer.cornerRadius = PH_PANEL_RADIUS;
    card.clipsToBounds = YES;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    blur.frame = card.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:blur];

    UIView *tint = [[UIView alloc] initWithFrame:card.bounds];
    tint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.30];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tint.userInteractionEnabled = NO;
    [card addSubview:tint];
    return card;
}

UIView *PHHairline(CGFloat w, CGFloat y) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 0.5)];
    v.backgroundColor = PH_HAIR;
    return v;
}

UIImage *PHIcon(NSString *symbolName, CGFloat size, UIColor *tint) {
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size];
    UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
    return tint ? [img imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal] : img;
}

UIButton *PHCircleButton(NSString *symbol, UIColor *bg, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, size, size);
    b.backgroundColor = bg;
    b.layer.cornerRadius = size / 2.0;
    b.tintColor = [UIColor whiteColor];
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.42
                                                                                weight:UIImageSymbolWeightBold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    return b;
}
