//
//  AudioManager.h
//  SFPlayer
//
//  Created by cdsf on 16/4/13.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^AudioManagerOutputBlock)(float *data, UInt32 numFrames, UInt32 numChannels);


@protocol AudioManagerDelegate <NSObject>

@property (readonly) UInt32             numOutputChannels;  //通道数
@property (readonly) Float64            samplingRate;       //采样率
@property (readonly) UInt32             numBytesPerSample;
@property (readonly) Float32            outputVolume;       //音量
@property (readonly) BOOL               playing;            //
@property (readonly, strong) NSString   *audioRoute;        //

@property (readwrite, copy) AudioManagerOutputBlock outputBlock;

- (BOOL) activateAudioSession;      //启用
- (void) deactivateAudioSession;    //禁用
- (BOOL) play;                      //开始输出
- (void) pause;                     //停止输出

@end


@interface AudioManager : NSObject
+ (id<AudioManagerDelegate>) audioManager;
@end
