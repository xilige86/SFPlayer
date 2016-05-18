//
//  MoviePlayerController.m
//  SFPlayer
//
//  Created by cdsf on 16/4/18.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import "MoviePlayerController.h"
#import "MovieDecoder.h"
#import "MovieGLView.h"
#import "AudioManager.h"

#define LOCAL_MIN_BUFFERED_DURATION   0.2       //本地最小缓冲时间
#define LOCAL_MAX_BUFFERED_DURATION   0.4       //本地最大缓冲时间
#define NETWORK_MIN_BUFFERED_DURATION 2.0       //网络最小缓冲时间
#define NETWORK_MAX_BUFFERED_DURATION 4.0       //网络最大缓存时长



#pragma mark - c methods
static NSString *formatTimeInterval(CGFloat seconds, BOOL isLeft)
{
    seconds = MAX(0, seconds);
    
    NSInteger s = seconds;
    NSInteger m = s / 60;
    NSInteger h = m / 60;
    
    s = s % 60;
    m = m % 60;
    
    NSMutableString *format = [(isLeft && seconds >= 0.5 ? @"-" : @"") mutableCopy];
    if (h != 0) [format appendFormat:@"%ld:%0.2ld", (long)h, (long)m];
    else        [format appendFormat:@"%ld", (long)m];
    [format appendFormat:@":%0.2ld", (long)s];
    
    return format;
}


static NSMutableDictionary * recordPlay;

@interface MoviePlayerController ()<MovieDecoderDelegate> {
    BOOL                _buffered;              //是否缓存中
    BOOL                _interrupted;           //是否中断解码
    BOOL                _disableUpdateHUD;      //是否禁止更新时间
    BOOL                _fullscreen;            //是否是全屏显示
    MovieDecoder        *_decoder;              //解码器对象
    dispatch_queue_t    _dispatchQueue;         //队列
    
    NSMutableArray      *_videoFrames;          //存储视频帧
    NSMutableArray      *_audioFrames;          //存储音频帧
    NSMutableArray      *_subtitles;            //存储字幕
    
    CGFloat             _bufferedDuration;      //当前缓冲时间
    CGFloat             _minBufferedDuration;   //最小缓冲时间
    CGFloat             _maxBufferedDuration;   //最大缓冲时间
    
    NSTimeInterval      _tickCorrectionTime;    //当前正确的系统时间
    NSTimeInterval      _tickCorrectionPosition;//当前正确的position
    NSUInteger          _tickCounter;           //tick计数
    
    NSData              *_currentAudioFrame;    //当前的音频帧
    NSUInteger          _currentAudioFramePos;  //当前音频帧位置
    
    CGFloat             _moviePosition;         //视频的位置

#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval      _debugStartTime;
    NSUInteger          _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif
    
    MovieGLView         *_glView;               //
    UIImageView         *_imageView;            //
    UILabel             *_subtitlesLabel;
}

@property (readwrite) BOOL playing;             //是否正在播放
@property (readwrite) BOOL decoding;            //解码状态判断
@property (readwrite, strong) ArtworkFrame *artworkFrame;
@property (nonatomic, readwrite) MoviePlayerState playerState;
@property (nonatomic, assign) CGRect movieSize;
@property (nonatomic, strong) UIView *presentView;

@end


@implementation MoviePlayerController

+ (void)initialize {
    if (!recordPlay)
        recordPlay = [NSMutableDictionary dictionary];
}

- (id)init:(UIView *)view {
    self = [super init];
    if (self) {
        if (view) {
            self.presentView = view;
            self.movieSize = view.bounds;
        }
        
        self.playerState = kMoviePlayerStateInitialized;
    }
    return self;
}

- (BOOL)openMedia:(NSString *)urlStr withOptions:(NSDictionary *)options {
    if (!urlStr || urlStr.length <= 0) {
        return NO;
    }
    
    //启用音频
    id<AudioManagerDelegate> audioManager = [AudioManager audioManager];
    [audioManager activateAudioSession];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerWillLoad:)]) {
        [self.delegate moviePlayerWillLoad:self];
    }
    
    __weak MoviePlayerController *weakSelf = self;
    
    //初始化解码器类
    MovieDecoder *decoder = [[MovieDecoder alloc] init];
    decoder.decoderDelegate = self;
    //中断回调
    decoder.interruptCallback = ^BOOL(){
        __strong MoviePlayerController *strongSelf = weakSelf;
        //
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    //开启异步线程来处理流解码
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSError *error = nil;
        //
        [decoder openFile:urlStr error:&error];
        //
        //返回主线程
        __strong MoviePlayerController *strongSelf = weakSelf;
        dispatch_sync(dispatch_get_main_queue(), ^{
            //
            [strongSelf setMovieDecoder:decoder withError:error];
        });
    });
    return YES;
}

#pragma mark - control init
- (void)loadView {
    //创建opengles view
    if (_decoder.validVideo) {
        _glView = [[MovieGLView alloc] initWithFrame:self.movieSize decoder:_decoder];
    }
    //创建imageview
    if (!_glView) {
        LoggerVideo(0, @"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:VideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:self.movieSize];
        _imageView.backgroundColor = [UIColor blackColor];
    }
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    //add view
    [self.presentView insertSubview:frameView atIndex:0];
    
    CGSize size = self.presentView.bounds.size;
    //初始化字幕显示label
    if (_decoder.subtitleStreamsCount) {
        _subtitlesLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size.height, size.width, 0)];
        _subtitlesLabel.numberOfLines = 0;
        _subtitlesLabel.backgroundColor = [UIColor clearColor];
        _subtitlesLabel.opaque = NO;
        _subtitlesLabel.adjustsFontSizeToFitWidth = NO;
        _subtitlesLabel.textAlignment = NSTextAlignmentCenter;
        _subtitlesLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _subtitlesLabel.textColor = [UIColor whiteColor];
        _subtitlesLabel.font = [UIFont systemFontOfSize:16];
        _subtitlesLabel.hidden = YES;
        
        [self.presentView addSubview:_subtitlesLabel];
    }
    if (_volumeView == nil) {
        _volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -10, 90, 20)];
        [self.presentView addSubview:_volumeView];
    }
}

//
- (UIView *)frameView
{
    return _glView ? _glView : _imageView;
}

#pragma mark - private methods
//是否中断解码
- (BOOL)interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

- (void)setMovieDecoder:(MovieDecoder *)decoder withError:(NSError *)error
{
    LoggerStream(2, @"setMovieDecoder");
    
    if (!error && decoder) {
        _decoder        = decoder;
        //创建队列
        _dispatchQueue  = dispatch_queue_create("SFMovie", DISPATCH_QUEUE_SERIAL);
//        _dispatchQueue  = dispatch_queue_create("SFMovie", DISPATCH_QUEUE_CONCURRENT);
        
        //音/视频帧数组
        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        //字幕流数组
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
        
        //网络判断
        if (_decoder.isNetwork) {
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
        } else {
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
        
        // allow to tweak some parameters at runtime
        if (self.minPlayableBufferSize) {
            _minBufferedDuration = self.minPlayableBufferSize;
        }
        if (self.maxPlayableBufferSize) {
            _minBufferedDuration = self.maxPlayableBufferSize;
        }
        //是否禁用反交错
        _decoder.disableDeinterlacing = self.disableDeinterlacing;
        
        if (_maxBufferedDuration < _minBufferedDuration) {
            _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        [self loadView];
        //加载完成
        self.duration = _decoder.duration;
        if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidLoad:error:)]) {
            [self.delegate moviePlayerDidLoad:self error:error];
        }
        
    } else {
        //打开流错误
        if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerError:)]) {
            [self.delegate moviePlayerError:error];
        }
    }
}

//开启异步解码帧
- (void) asyncDecodeFrames
{
    if (self.decoding) //正在解码中...
        return;
    
    __weak MoviePlayerController *weakSelf = self;
    __weak MovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    //开启异步线程
    dispatch_async(_dispatchQueue, ^{
        {
//            __strong MoviePlayerController *strongSelf = weakSelf;
//            if (!strongSelf.playing)
//                return;
        }
        
        BOOL good = YES;
        while (good) {
            good = NO;
            //线程池
            @autoreleasepool {
                __strong MovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    //get decode
                    NSArray *frames = [decoder decodeFrames:duration];
                    
                    if (frames.count) {
                        __strong MoviePlayerController *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames]; //add frame to array
                    }
                    [self showFPS];
                }
            }
        }
        
        {
            __strong MoviePlayerController *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

//同步取帧，将frames add to array
- (BOOL)addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) { //
        @synchronized(_videoFrames) { //视频加锁
            for (MovieFrame *frame in frames) {
                if (frame.type == MovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
            }
        }
    }
    
    if (_decoder.validAudio) { //
        @synchronized(_audioFrames) { //音频加锁
            for (MovieFrame *frame in frames) {
                if (frame.type == MovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
            }
        }
        
        if (!_decoder.validVideo) {
            for (MovieFrame *frame in frames)
                if (frame.type == MovieFrameTypeArtwork)
                    self.artworkFrame = (ArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        @synchronized(_subtitles) { //字幕加锁
            for (MovieFrame *frame in frames) {
                if (frame.type == MovieFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
            }
        }
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

//
- (void) tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        _tickCorrectionTime = 0;
        _buffered = NO;
        
        //完成加载，并开始播放
        self.playerState = kMoviePlayerStatePlaying;
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        const NSUInteger leftFrames = (_decoder.validVideo ? _videoFrames.count : 0) + (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) { //是否有音频和视频流返回
            //如果没有返回，则判断是否是到末尾
            if (_decoder.isEOF) { //末尾
                [self pause];
                [self updatePlaytime];
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) { //加载
                _buffered = YES;
                self.playerState = kMoviePlayerStateLoading;
            }
        }
        
        if (_buffered) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidBufferingProgressChange:progress:)]) {
                NSLog(@"正在缓存进度：%f",_bufferedDuration / _minBufferedDuration * 100);
                [self.delegate moviePlayerDidBufferingProgressChange:self progress:(_bufferedDuration / _minBufferedDuration * 100)];
            }
        }
        
        if (!leftFrames || !(_bufferedDuration > _minBufferedDuration)) {
            //继续读取
            [self asyncDecodeFrames];
        }
        
        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }
    
    if ((_tickCounter++ % 3) == 0) {
        [self updatePlaytime];
    }
    //
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidStateChange:)]) {
        [self.delegate moviePlayerDidStateChange:self];
    }
}

//当前帧
- (CGFloat)presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        VideoFrame *frame;
        
        @synchronized(_videoFrames) {
            if (_videoFrames.count > 0) {
                //取出第一帧，将取出的帧从数组中移出，并减去相应帧时长
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {
        if (self.artworkFrame) {
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }
    
    if (_decoder.validSubtitles)
        [self presentSubtitles];
    
#ifdef DEBUG
    if (self.playing && _debugStartTime < 0)
        _debugStartTime = [NSDate timeIntervalSinceReferenceDate] - _moviePosition;
#endif
    
    return interval;
}

//返回当前校正的时间
- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    if (correction > 1.f || correction < -1.f) {
        LoggerStream(1, @"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

//将当前帧添加到view
- (CGFloat)presentVideoFrame:(VideoFrame *)frame
{
    if (_glView) {
        //帧渲染
        [_glView render:frame];
    } else {
        VideoFrameRGB *rgbFrame = (VideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
    
    return frame.duration;
}

//将当前字幕显示到subtitle label上
- (void) presentSubtitles
{
    NSArray *actual, *outdated;
    
    if ([self subtitleForPosition:_moviePosition
                           actual:&actual
                         outdated:&outdated]){
        
        if (outdated.count) {
            @synchronized(_subtitles) {
                [_subtitles removeObjectsInArray:outdated];
            }
        }
        
        if (actual.count) {
            NSMutableString *ms = [NSMutableString string];
            for (SubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
                if (ms.length) [ms appendString:@"\n"];
                [ms appendString:subtitle.text];
            }
            
            if (![_subtitlesLabel.text isEqualToString:ms]) {
                CGSize size = [ms sizeWithFont:_subtitlesLabel.font
                             constrainedToSize:CGSizeMake(self.movieSize.size.width, self.movieSize.size.height * 0.5)
                                 lineBreakMode:NSLineBreakByTruncatingTail];
                _subtitlesLabel.text = ms;
                _subtitlesLabel.frame = CGRectMake(0, self.movieSize.size.height - size.height - 10,
                                                   self.movieSize.size.width, size.height);
                _subtitlesLabel.hidden = NO;
            }
        } else {
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
        }
    }
}

//是否有字幕流输出
- (BOOL)subtitleForPosition: (CGFloat) position
                     actual: (NSArray **) pActual
                   outdated: (NSArray **) pOutdated
{
    if (!_subtitles.count)
        return NO;
    
    NSMutableArray *actual = nil;
    NSMutableArray *outdated = nil;
    
    for (SubtitleFrame *subtitle in _subtitles) {
        if (position < subtitle.position) {
            break; // assume what subtitles sorted by position
        } else if (position >= (subtitle.position + subtitle.duration)) {
            if (pOutdated) {
                if (!outdated)
                    outdated = [NSMutableArray array];
                [outdated addObject:subtitle];
            }
        } else {
            if (pActual) {
                if (!actual)
                    actual = [NSMutableArray array];
                [actual addObject:subtitle];
            }
        }
    }
    
    if (pActual) *pActual = actual;
    if (pOutdated) *pOutdated = outdated;
    
    return actual.count || outdated.count;
}

//设置音频是否可用
- (void)enableAudio:(BOOL)on
{
    id<AudioManagerDelegate> audioManager = [AudioManager audioManager];
    //
    if (on && _decoder.validAudio) { //开启音频
        //音频输出回调
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            //
            [self audioCallbackFillData:outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        LoggerAudio(2, @"audio device smr: %d fmt: %d chn: %d",
                    (int)audioManager.samplingRate,
                    (int)audioManager.numBytesPerSample,
                    (int)audioManager.numOutputChannels);
    } else { //关闭音频，停止输出
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

//
- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    if (_buffered) {
        //为新申请的内存做初始化工作
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    //
    @autoreleasepool {
        while (numFrames > 0) {
            if (!_currentAudioFrame) {
                @synchronized(_audioFrames) {
                    NSUInteger count = _audioFrames.count;
                    //
                    if (count > 0) {
                        AudioFrame *frame = _audioFrames[0];
#ifdef DUMP_AUDIO_DATA
                        LoggerAudio(2, @"Audio frame position: %f", frame.position);
#endif
                        if (_decoder.validVideo) { //
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -0.1) {
                                
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (outrun) wait %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 1;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 0.1 && count > 1) {
                                
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (lags) skip %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 2;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                //
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                //
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
#ifdef DEBUG
                _debugAudioStatus = 3;
                _debugAudioStatusTS = [NSDate date];
#endif
                break;
            }
        }
    }
}

//
- (void)enableUpdatePlaytime
{
    _disableUpdateHUD = NO;
}

//实时返回播放时间
- (void)updatePlaytime {
    //
    self.duration = _decoder.duration;
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidCurrentTimeChange:position:)]) {
        [self.delegate moviePlayerDidCurrentTimeChange:self position:position];
    }
    
    //播放
    if (_decoder.isEOF) {
        self.playerState = kMoviePlayerStateFinishedPlayback;
        if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidStateChange:)]) {
            [self.delegate moviePlayerDidStateChange:self];
        }
    }
}

//更新位置
- (void)updatePosition:(CGFloat)position playMode:(BOOL)playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak MoviePlayerController *weakSelf = self;
    //开启异步线程
    dispatch_async(_dispatchQueue, ^{
        if (playMode) { //播放
            {
                __strong MoviePlayerController *strongSelf = weakSelf;
                if (!strongSelf) return;
                //
                [strongSelf setDecoderPosition: position];
            }
            
            //返回主线程
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong MoviePlayerController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                }
            });
        } else { //未播放
            {
                __strong MoviePlayerController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            //返回主线程
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong MoviePlayerController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf enableUpdatePlaytime];
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    [strongSelf updatePlaytime];
                }
            });
        }
    });
}

//释放
- (void)freeBufferedFrames
{
    //加锁
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    
    if (_subtitles) {
        @synchronized(_subtitles) {
            [_subtitles removeAllObjects];
        }
    }
    
    _bufferedDuration = 0;
}

- (void)setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void)setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

//调用解码器并返回帧数组
- (BOOL)decodeFrames
{
    NSArray *frames = nil;
    //读取解码帧
    if (_decoder.validVideo || _decoder.validAudio) {
        frames = [_decoder decodeFrames:0];
        [self showFPS];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (void)showFPS {
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidFramerateChange:framerate:)]) {
        [self.delegate moviePlayerDidFramerateChange:self framerate:_decoder.fps];
    }
}

#pragma mark - public methods
- (BOOL)play
{
    if (self.playing)
        return NO;
    
    if (!_decoder.validVideo && !_decoder.validAudio) {
        return NO;
    }
    
    if (_interrupted) //如果中断
        return NO;
    
    self.playing = YES;
    _interrupted = NO;
    //校正时间
    _tickCorrectionTime = 0;
    _tickCounter = 0;
    
#ifdef DEBUG
    _debugStartTime = -1;
#endif
    
    [self asyncDecodeFrames];   //
    
    //开启时间计时器
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    if (_decoder.validAudio)
        [self enableAudio:YES];
    
    LoggerStream(1, @"play movie");
    return YES;
}

- (void)pause
{
    if (!self.playing)
        return;
    
    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    
    self.playerState = kMoviePlayerStatePaused;
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidStateChange:)]) {
        [self.delegate moviePlayerDidStateChange:self];
    }
    LoggerStream(1, @"pause movie");
}

//设置播放进度
- (void)setMoviePosition:(CGFloat)position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    _disableUpdateHUD = YES;
    [self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        //
        [self updatePosition:position playMode:playMode];
    });
}

//恢复播放
- (void)restorePlay {
    NSNumber *n = [recordPlay valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}

//记录播放
- (void)recordPlay {
    if (_decoder) {
        
        [self pause];
        
        if (_moviePosition == 0 || _decoder.isEOF)
            [recordPlay removeObjectForKey:_decoder.path];
        else if (!_decoder.isNetwork)
            [recordPlay setValue:[NSNumber numberWithFloat:_moviePosition]
                        forKey:_decoder.path];
    }
}

- (MoviePlayerState)playerState {
    return self.playerState;
}

- (void)fullScreen:(BOOL)enter {
    _fullscreen = enter;
    UIView *frameView = [self frameView];
    if (enter && frameView.contentMode == UIViewContentModeScaleAspectFit) {
        frameView.contentMode = UIViewContentModeScaleAspectFill;
        if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidEnterFullscreenMode:)]) {
            [self.delegate moviePlayerDidEnterFullscreenMode:self];
        }
    } else {
        frameView.contentMode = UIViewContentModeScaleAspectFit;
        if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerDidExitFullscreenMode:)]) {
            [self.delegate moviePlayerDidExitFullscreenMode:self];
        }
    }
    //显示隐藏状态栏
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:enter withAnimation:UIStatusBarAnimationNone];
}

- (BOOL)isFullscreen {
    return _fullscreen;
}

- (void)setBrightness:(float)brightness {
    
    [[UIScreen mainScreen] setBrightness:brightness];
}

- (float)brightness {
    float value = [UIScreen mainScreen].brightness;
    return value;
}

- (void)setContrast:(float)contrast {
    _glView.contrast = contrast;
//    if (_decoder) {
//        _decoder.contrast = contrast;
//    }
}

- (void)setSaturation:(float)saturation {
//    _glView.saturation = saturation;
    if (_decoder) {
        _decoder.contrast = saturation;
    }
}

- (NSArray *)audioList {
    NSArray *audios = _decoder.info[@"audio"];
    return audios;
}

- (NSInteger)currentAudio {
    return _decoder.selectedAudioStream;
}

- (void)switchAudioTracker:(int)index {
    //获取当前已经选中的音频流
    NSInteger selected = _decoder.selectedAudioStream;
    if (index != selected) {
        _decoder.selectedAudioStream = index;
    }
}
- (void)setVolume:(float)fact
{
    UISlider* volumeViewSlider = nil;
    for (UIView *view in [_volumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            volumeViewSlider = (UISlider*)view;
            break;
        }
    }
    volumeViewSlider.value=fact;
    [volumeViewSlider sendActionsForControlEvents:UIControlEventValueChanged];
}
- (float)currentVolume
{
    UISlider* volumeViewSlider = nil;
    for (UIView *view in [_volumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            volumeViewSlider = (UISlider*)view;
            break;
        }
    }
    float systemVolume = volumeViewSlider.value;
    return systemVolume;
    
}
-(void)playSpeedCustom:(float)speed
{
    _decoder.speedCount = speed;
}
- (float)playbackSpeed
{
    return _decoder.speedCount;
}
-(NSArray *)subtitleTracks
{
    
    return _decoder.subtitleArray;
    
}
-(NSInteger)currentSubtitleTrack
{
    
    return _decoder.selectedSubtitleStream;
    
}
-(void)selectSubtitle:(NSInteger)subtitleStream
{
    NSAssert(subtitleStream >= _decoder.subtitleArray.count, @"所选择的字幕索引越界");
    if (_decoder.subtitleArray.count > 0 && subtitleStream < _decoder.subtitleArray.count) {
     _decoder.selectedSubtitleStream = subtitleStream;
    }
    
}

- (NSString *)formatTime:(float)seconds isLeft:(BOOL)left {
    NSString *timeStr = formatTimeInterval(seconds, left);
    return timeStr;
}

//快进
- (void)forwardDidTouch: (CGFloat) value
{
    [self setMoviePosition: _moviePosition + value];
}

//快退
- (void)rewindDidTouch: (CGFloat) value
{
    [self setMoviePosition: _moviePosition - value];
}

#pragma mark - moviedecoder delegate
- (void)movieDecoderDidOccurError:(NSError *)error {
    if (self.delegate && [self.delegate respondsToSelector:@selector(moviePlayerError:)]) {
        [self.delegate moviePlayerError:error];
    }
}



@end
