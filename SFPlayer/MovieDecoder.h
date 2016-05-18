//
//  MovieDecoder.h
//  SFPlayer
//
//  Created by cdsf on 16/4/11.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MovieErros.h"

typedef enum {
    MovieFrameTypeAudio,
    MovieFrameTypeVideo,
    MovieFrameTypeArtwork,
    MovieFrameTypeSubtitle,
    MovieFrameTypeAd
} MovieFrameType;

typedef enum {
    VideoFrameFormatRGB,
    VideoFrameFormatYUV
} VideoFrameFormat;


@interface MovieFrame : NSObject
@property (nonatomic, readonly) MovieFrameType type;
@property (nonatomic, readonly) CGFloat position;
@property (nonatomic, readonly) CGFloat duration;
@end


@interface AudioFrame : MovieFrame
@property (readonly, nonatomic, strong) NSData *samples;
@end


@interface VideoFrame : MovieFrame
@property (nonatomic, readonly) VideoFrameFormat format;
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@end


@interface VideoFrameRGB : VideoFrame
@property (nonatomic, readonly) NSUInteger lineSize;
@property (nonatomic, readonly, strong) NSData *rgb;
- (UIImage *)asImage;
@end

@interface VideoFrameYUV : VideoFrame
@property (nonatomic, readonly, strong) NSData *luma;       //表示“Y”明亮度
@property (nonatomic, readonly, strong) NSData *chromaB;    //"U"色彩及饱和度
@property (nonatomic, readonly, strong) NSData *chromaR;    //"V"色彩及饱和度
@end


@interface ArtworkFrame : MovieFrame
@property (nonatomic, readonly, strong) NSData *picture;
- (UIImage *)asImage;
@end

@interface SubtitleFrame : MovieFrame
@property (nonatomic, readonly, strong) NSString *text;
@end


//解码中断时回调
typedef BOOL(^MovieDecoderInterruptCallback)();

@protocol MovieDecoderDelegate <NSObject>

- (void)movieDecoderDidOccurError:(NSError *)error;

@end


@interface MovieDecoder : NSObject
//property
@property (readonly, nonatomic, strong) NSString *path;
@property (readonly, nonatomic) BOOL isEOF;
@property (readwrite,nonatomic) CGFloat position;   //当前进度
@property (readonly, nonatomic) CGFloat duration;   //总长度
@property (readonly, nonatomic) CGFloat fps;        //帧率
@property (readonly, nonatomic) CGFloat sampleRate; //采样率
@property (readonly, nonatomic) NSUInteger frameWidth;
@property (readonly, nonatomic) NSUInteger frameHeight;
@property (readonly, nonatomic) NSUInteger audioStreamsCount;
@property (readwrite,nonatomic) NSInteger selectedAudioStream;      //选择音频流
@property (readonly, nonatomic) NSUInteger subtitleStreamsCount;
@property (readwrite,nonatomic) NSInteger selectedSubtitleStream;   //选择字幕流
@property (readonly, nonatomic) BOOL validVideo;
@property (readonly, nonatomic) BOOL validAudio;
@property (readonly, nonatomic) BOOL validSubtitles;
@property (readonly, nonatomic, strong) NSDictionary *info;         //获取视频信息
@property (readonly, nonatomic, strong) NSString *videoStreamFormatName;
@property (readonly, nonatomic) BOOL isNetwork;
@property (readonly, nonatomic) CGFloat startTime;
@property (readwrite, nonatomic) BOOL disableDeinterlacing;
@property (assign, nonatomic) NSInteger brightness;   //亮度
@property (assign, nonatomic) int contrast;     //对比度
@property (assign, nonatomic) int saturation;   //饱和度
@property (readwrite, nonatomic, strong) MovieDecoderInterruptCallback interruptCallback;
@property (nonatomic, assign)    float speedCount; // 视频播放速率
@property (nonatomic, strong,readonly)   NSArray *subtitleArray;//字幕数组
@property (assign, nonatomic) id<MovieDecoderDelegate> decoderDelegate;
//methods
+ (id)movieDecoderWithContentPath:(NSString *)path
                             error:(NSError **)perror;
- (BOOL)openFile:(NSString *)path
            error:(NSError **)perror;
-(void)closeFile;
- (BOOL)setupVideoFrameFormat:(VideoFrameFormat)format;
- (NSArray *)decodeFrames:(CGFloat)minDuration;

@end


@interface MovieSubtitleASSParser : NSObject

+ (NSArray *) parseEvents: (NSString *) events;
+ (NSArray *) parseDialogue: (NSString *) dialogue
                  numFields: (NSUInteger) numFields;
+ (NSString *) removeCommandsFromEventText: (NSString *) text;

@end

