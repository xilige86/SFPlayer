//
//  MovieGLView.h
//  SFPlayer
//
//  Created by cdsf on 16/4/14.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <UIKit/UIKit.h>

@class VideoFrame;
@class MovieDecoder;


@interface MovieGLView : UIView

@property (nonatomic, assign) float contrast;
@property (nonatomic, assign) float saturation;

- (id)initWithFrame:(CGRect)frame decoder:(MovieDecoder *)decoder;
- (void)render:(VideoFrame *)frame;
@end
