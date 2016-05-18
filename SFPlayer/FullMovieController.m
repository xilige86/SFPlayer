//
//  FullMovieController.m
//  SFPlayer
//
//  Created by cdsf on 16/4/21.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import "FullMovieController.h"
#import "MoviePlayerController.h"
#import <MediaPlayer/MPVolumeView.h>


NSString * const KfMovieParameterMinBufferedDuration = @"KMovieParameterMinBufferedDuration";
NSString * const KfMovieParameterMaxBufferedDuration = @"KMovieParameterMaxBufferedDuration";
NSString * const KfMovieParameterDisableDeinterlacing = @"KMovieParameterDisableDeinterlacing";

@interface FullMovieController ()<MoviePlayerDelegate> {
    MoviePlayerController *moviePlayer;
}

@end

@implementation FullMovieController

//
+ (instancetype)playerUrl:(NSString *)url paramters:(NSDictionary *)param
{
    return [[FullMovieController alloc] initWithContentPath:url parameters:param];
}

- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        moviePlayer = [[MoviePlayerController alloc] init:self.view];
        moviePlayer.delegate = self;
        [moviePlayer openMedia:path withOptions:parameters];
        
        UISlider *slider0 = [[UISlider alloc] initWithFrame:CGRectMake(10, 100, 150, 20)];
        slider0.maximumValue = 1;
        slider0.minimumValue = 0;
        slider0.value = 0.5;
        [slider0 addTarget:self action:@selector(change0:) forControlEvents:UIControlEventValueChanged];
        [self.view addSubview:slider0];
        
        UISlider *slider1 = [[UISlider alloc] initWithFrame:CGRectMake(10, 130, 150, 20)];
        slider1.maximumValue = 4;
        slider1.minimumValue = 0;
        slider1.value = 1.0;
        [slider1 addTarget:self action:@selector(change1:) forControlEvents:UIControlEventValueChanged];
        [self.view addSubview:slider1];
        
        UISlider *slider2 = [[UISlider alloc] initWithFrame:CGRectMake(10, 160, 150, 20)];
        slider2.maximumValue = 2;
        slider2.minimumValue = 0;
        slider2.value = 1.0;
        [slider2 addTarget:self action:@selector(change2:) forControlEvents:UIControlEventValueChanged];
        [self.view addSubview:slider2];
    }
    return self;
}

- (void)change0:(UISlider *)slider {
    moviePlayer.brightness = slider.value;
}

- (void)change1:(UISlider *)slider {
    moviePlayer.contrast = slider.value;
}

- (void)change2:(UISlider *)slider {
    moviePlayer.saturation = slider.value;
}

#pragma mark - movieplayer delegate
//error handler
- (void)moviePlayerError:(NSError *)error {
    NSLog(@"错误：%ld, %@", (long)error.code, error.userInfo);
}
//will load movie source
- (void)moviePlayerWillLoad:(MoviePlayerController *)playerController{
    NSLog(@"开始加载视频");
    [playerController setVolume:0.8];
}
//did load movie source
- (void)moviePlayerDidLoad:(MoviePlayerController *)playerController error:(NSError *)error {
    [playerController play];
    playerController.brightness = 0.8;
    playerController.contrast = 1;
    playerController.saturation = 1;
}
//state changed
- (void)moviePlayerDidStateChange:(MoviePlayerController *)playerController {
    
}
//current play time changed
- (void)moviePlayerDidCurrentTimeChange:(MoviePlayerController *)playerController  position:(NSTimeInterval)position {
    
}

//current buffering progress changed
- (void)moviePlayerDidBufferingProgressChange:(MoviePlayerController *)playerController progress:(double)progress {
    NSLog(@"=-=-=-=-=-=-=-=-=-=-=-=-=: %.1f", progress);
}

//real framerate changed
- (void)moviePlayerDidFramerateChange:(MoviePlayerController *)playerController framerate:(NSInteger)framerate {
    
}
// enter or exit full screen mode
- (void)moviePlayerDidEnterFullscreenMode:(MoviePlayerController *)controller {
    
}
- (void)moviePlayerDidExitFullscreenMode:(MoviePlayerController *)controller {
    
}


@end
