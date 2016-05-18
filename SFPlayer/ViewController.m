//
//  ViewController.m
//  SFPlayer
//
//  Created by cdsf on 16/4/11.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import "ViewController.h"
#import "MovieViewController.h"
#import "FullMovieController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    UIButton *btnPaly = [UIButton buttonWithType:UIButtonTypeCustom];
    btnPaly.frame = CGRectMake(100, 100, 100, 32);
    btnPaly.backgroundColor = [UIColor purpleColor];
    [btnPaly setTitle:@"play" forState:UIControlStateNormal];
    [btnPaly addTarget:self action:@selector(playPress) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btnPaly];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)playPress {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    NSString *urlString = @"http://ktv039.cdnak.ds.kylintv.net/nlds/kylin/pxhkus/as/live/pxhkus_4.m3u8";
//    NSString *urlString = @"http://dlhls.cdn.zhanqi.tv/zqlive/45188_oT6Ed.m3u8";
//    NSString *urlString = @"http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8";
//    NSString *urlString = @"http://demo.cuplayer.com:8011/hls2-vod/test.mp4.m3u8";
//    NSString *urlString = @"http://dlhls.cdn.zhanqi.tv/zqlive/21333_CvnhE.m3u8";
//    NSString *urlString = @"rtsp://184.72.239.149/vod/mp4:BigBuckBunny_175k.mov";
    // increase buffering for .wmv, it solves problem with delaying audio frames
//    if ([urlString.pathExtension isEqualToString:@"wmv"])
//        parameters[KMovieParameterMinBufferedDuration] = @(5.0);
//    
//    // disable deinterlacing for iPhone, because it's complex operation can cause stuttering
//    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
//        parameters[KMovieParameterDisableDeinterlacing] = @(YES);
//    
//    MovieViewController *movieVC = [MovieViewController playerUrl:urlString paramters:parameters];
//    [self presentViewController:movieVC animated:YES completion:nil];
    
    
    
    
    
    
    // increase buffering for .wmv, it solves problem with delaying audio frames
    if ([urlString.pathExtension isEqualToString:@"wmv"])
        parameters[KfMovieParameterMinBufferedDuration] = @(5.0);
    
    // disable deinterlacing for iPhone, because it's complex operation can cause stuttering
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        parameters[KfMovieParameterDisableDeinterlacing] = @(YES);
    FullMovieController *movieVC = [FullMovieController playerUrl:urlString paramters:parameters];
    [self presentViewController:movieVC animated:YES completion:nil];
}

@end
