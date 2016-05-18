//
//  FullMovieController.h
//  SFPlayer
//
//  Created by cdsf on 16/4/21.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <UIKit/UIKit.h>


extern NSString * const KfMovieParameterMinBufferedDuration;    // Float
extern NSString * const KfMovieParameterMaxBufferedDuration;    // Float
extern NSString * const KfMovieParameterDisableDeinterlacing;   // BOOL

@interface FullMovieController : UIViewController
+ (instancetype)playerUrl:(NSString *)url paramters:(NSDictionary *)param;
@end
