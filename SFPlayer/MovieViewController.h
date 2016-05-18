//
//  MovieViewController.h
//  SFPlayer
//
//  Created by cdsf on 16/4/11.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString * const KMovieParameterMinBufferedDuration;    // Float
extern NSString * const KMovieParameterMaxBufferedDuration;    // Float
extern NSString * const KMovieParameterDisableDeinterlacing;   // BOOL

@interface MovieViewController : UIViewController<UITableViewDataSource, UITableViewDelegate>

@property (readonly) BOOL playing;
+ (instancetype)playerUrl:(NSString *)url paramters:(NSDictionary *)param;
- (void)play;   //播放
- (void)pause;  //暂停

@end

