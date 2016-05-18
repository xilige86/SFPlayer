//
//  MoviePlayerController.h
//  SFPlayer
//
//  Created by cdsf on 16/4/18.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

@class MoviePlayerController;

/**
 * movie player states
 **/
typedef NS_ENUM(NSInteger, MoviePlayerState) {
    kMoviePlayerStateInitialized=0,     //init
    kMoviePlayerStateLoading,           //loading
    kMoviePlayerStatePlaying,           //playing
    kMoviePlayerStatePaused,            //pause
    kMoviePlayerStateFinishedPlayback,  //finished
    kMoviePlayerStateStoped,            //stop
    kMoviePlayerStateUnknown=0xff       //unknown
};

typedef NS_ENUM(NSInteger, MoviePalyerError) {
    MoviePalyerErrorURL=0,              //
    
};


@protocol MoviePlayerDelegate <NSObject>

//error handler
- (void)moviePlayerError:(NSError *)error;
//will load movie source
- (void)moviePlayerWillLoad:(MoviePlayerController *)playerController;
//did load movie source
- (void)moviePlayerDidLoad:(MoviePlayerController *)playerController error:(NSError *)error;
//state changed
- (void)moviePlayerDidStateChange:(MoviePlayerController *)playerController;
//current play time changed
- (void)moviePlayerDidCurrentTimeChange:(MoviePlayerController *)playerController  position:(NSTimeInterval)position;
//current buffering progress changed
- (void)moviePlayerDidBufferingProgressChange:(MoviePlayerController *)playerController progress:(double)progress;
////real bitrate changed
//- (void)moviePlayerDidBitrateChange:(MoviePlayerController *)playerController bitrate:(NSInteger)bitrate;
//real framerate changed
- (void)moviePlayerDidFramerateChange:(MoviePlayerController *)playerController framerate:(NSInteger)framerate;
// enter or exit full screen mode
- (void)moviePlayerDidEnterFullscreenMode:(MoviePlayerController *)controller;
- (void)moviePlayerDidExitFullscreenMode:(MoviePlayerController *)controller;

@end


@interface MoviePlayerController : NSObject

@property (nonatomic, readonly) NSString *mediaUrl;
@property (nonatomic, weak) id <MoviePlayerDelegate> delegate;
@property (nonatomic, assign) BOOL shouldAutoPlay;          // default NO
@property (readonly) BOOL playing;

/*
 * Get/Set the minmum playable buffer size, default size is 0.
 * @size - the minmum playable buffer size.
 * @value 0 indicates that minimum playable buffer size feature is disabled.
 */
@property (nonatomic) unsigned long long minPlayableBufferSize;
@property (nonatomic) unsigned long long maxPlayableBufferSize;
/**
 * Get/Set the video decoder disableDeinterlacing
 */
@property (nonatomic, assign) BOOL disableDeinterlacing;

@property (nonatomic, strong) NSArray *subtitleTracks;
@property (nonatomic, assign) NSInteger currentSubtitleTrack;

/**
 * movie codec bitrate and video frame rate
 */
@property (nonatomic, readonly) NSInteger avBitrate;
@property (nonatomic, readonly) NSInteger avFramerate;
/**
 * 调整视频显示器的对比度和饱和度
 * @contrast: 0.0 to 4.0, default 1.0
 * @saturation: 0.0 to 2.0, default 1.0
 **/
@property (nonatomic, assign) float contrast;
@property (nonatomic, assign) float saturation;
/*
 * Adjust the screen's brightness (0 to 1).
 */
@property (nonatomic, assign) float brightness;
/*
 * system volume view
 */
@property (nonatomic ,strong) MPVolumeView *volumeView ;
/*
 *movie source duration
 */
@property (nonatomic, assign) CGFloat duration;
/*
 * Init MoviePlayerController object.
 * @If failed, return nil, otherwise return initialized MoviePlayerController instance.
 */
- (id)init:(UIView *)view;

/*
 * Open media file at path.
 * @url - path to media source.
 * @options - A dictionary filled with AVFormatContext and demuxer-private options.
 * @If failed, return NO, otherwise return YES.
 */
- (BOOL)openMedia:(NSString *)urlStr withOptions:(NSDictionary *)options;
/*
 * Query MoviePlayer current state.
 * @This function return AVPlayer current state info.
 */
- (MoviePlayerState)playerState;

/*
 * Start playback.
 * @ti - playback start position (0 ~ duration).
 * @If failed, return NO, otherwise return YES.
 */
- (BOOL)play;
/*
 * Pause playback.
 * @This function does not return a value.
 */
- (void)pause;

/*
 * set play progress,e.g forwardDidTouch rewindDidTouch and progress change value
 */
- (void)setMoviePosition:(CGFloat)position;

/**
 * restore pre play
 */
- (void)restorePlay;
/**
 * record current play
 */
- (void)recordPlay;

/*
 * Volume control - GET.
 * @This function returns the current volume factor (0~1).
 */
- (float)currentVolume;
/*
 * Volume control - SET.
 * @fact - volume factor (0~1).
 * @This function does not return a value.
 */
- (void)setVolume:(float)fact;
/*
 * Enter or exit full screen mode.
 * @enter - YES to enter, NO to exit.
 * @This function does not return a value.
 */
- (void)fullScreen:(BOOL)enter;

/*
 * Determine moviePlayer whether or not is in full screen mode.
 * @If it is in full screen mode, return YES, otherwise return NO.
 */
- (BOOL)isFullscreen;
/*
 *  Enter you want the video play speed (0.5~2.0f).
 *
 */
-(void)playSpeedCustom:(float)speed;
/*
 * Get playback speed.
 * @This function return current playback speed (0.5~2.0f).
 * Default 1.0
 */
- (float)playbackSpeed;
/*
 * get all subtitles
 */
-(NSArray *)subtitleTracks;
/*
 *  current subtitle 
 */
-(NSInteger)currentSubtitleTrack;
/*
 * Select subtitle
 */
-(void)selectSubtitle:(NSInteger)subtitleStream;
/*
 * get all audios
 */
- (NSArray *)audioList;
/*
 * get current audio index
 */
- (NSInteger)currentAudio;
/*
 * Switch to special audio tracker
 * @index: index of the audio tracker.
 */
- (void)switchAudioTracker:(int)index;
/*
 * 转换时间格式
 * @seconds: time seconds
 * @left:    Diminishing to display
 */
- (NSString *)formatTime:(float)seconds isLeft:(BOOL)left;
/*
 *  Enter forward seconds you want
 *  @value : seconds
 */
- (void)forwardDidTouch: (CGFloat) value;
/*
 *  Enter rewind seconds you want
 *  @value : seconds
 */
- (void)rewindDidTouch: (CGFloat) value;

@end
