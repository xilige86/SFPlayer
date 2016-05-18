//
//  MovieViewController.m
//  SFPlayer
//
//  Created by cdsf on 16/4/11.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import "MovieViewController.h"
#import "MovieDecoder.h"
#import "MovieGLView.h"
#import "AudioManager.h"


NSString * const KMovieParameterMinBufferedDuration = @"KMovieParameterMinBufferedDuration";
NSString * const KMovieParameterMaxBufferedDuration = @"KMovieParameterMaxBufferedDuration";
NSString * const KMovieParameterDisableDeinterlacing = @"KMovieParameterDisableDeinterlacing";

////////////////////////////////////////////////////////////////////////////////

enum {
    MovieInfoSectionGeneral,  //通用
    MovieInfoSectionVideo,    //视频
    MovieInfoSectionAudio,    //音频
    MovieInfoSectionSubtitles,//字幕
    MovieInfoSectionMetadata, //元数据
    MovieInfoSectionCount,    //
};

enum {
    MovieInfoGeneralFormat,   //
    MovieInfoGeneralBitrate,  //
    MovieInfoGeneralCount,    //
};

////////////////////////////////////////////////////////////////////////////////

static NSMutableDictionary * gHistory;

#define LOCAL_MIN_BUFFERED_DURATION   0.2       //本地最小缓存时长
#define LOCAL_MAX_BUFFERED_DURATION   0.4       //本地最大缓存时长
#define NETWORK_MIN_BUFFERED_DURATION 2.0       //网络最小缓存时长
#define NETWORK_MAX_BUFFERED_DURATION 4.0       //网络最大缓存时长



#pragma mark - c methods
////////////////////////////////////////////////////////////////////////////////

static NSString * formatTimeInterval(CGFloat seconds, BOOL isLeft)
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

////////////////////////////////////////////////////////////////////////////////




@interface MovieViewController ()<MovieDecoderDelegate> {
    MovieDecoder        *_decoder;              //解码对象
    dispatch_queue_t    _dispatchQueue;         //队列
    NSMutableArray      *_videoFrames;          //视频帧
    NSMutableArray      *_audioFrames;          //音频帧
    NSMutableArray      *_subtitles;            //字幕
    NSData              *_currentAudioFrame;    //当前的音频帧
    NSUInteger          _currentAudioFramePos;  //当前音频帧位置
    CGFloat             _moviePosition;         //视频的位置
    BOOL                _disableUpdateHUD;      //显示加载
    NSTimeInterval      _tickCorrectionTime;    //当前正确的系统时间
    NSTimeInterval      _tickCorrectionPosition;//
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _hiddenHUD;             //隐藏加载
    BOOL                _fitMode;               //适应模式
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;           //是否中断解码
    
    MovieGLView         *_glView;
    UIImageView         *_imageView;
    UIView              *_topHUD;
    UIToolbar           *_topBar;
    UIToolbar           *_bottomBar;
    UISlider            *_progressSlider;
    
    UIBarButtonItem     *_playBtn;
    UIBarButtonItem     *_pauseBtn;
    UIBarButtonItem     *_rewindBtn;
    UIBarButtonItem     *_fforwardBtn;
    UIBarButtonItem     *_spaceItem;
    UIBarButtonItem     *_fixedSpaceItem;
    
    UIButton            *_doneButton;
    UILabel             *_progressLabel;
    UILabel             *_leftLabel;
    UILabel             *_bitrateLabel;         //
    UIButton            *_infoButton;
    UITableView         *_tableView;
    UIActivityIndicatorView *_activityIndicatorView;
    UILabel             *_subtitlesLabel;
    
    UITapGestureRecognizer *_tapGestureRecognizer;
    UITapGestureRecognizer *_doubleTapGestureRecognizer;
    UIPanGestureRecognizer *_panGestureRecognizer;
    
#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval      _debugStartTime;
    NSUInteger          _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif
    
    CGFloat             _bufferedDuration;          //记录当前缓存时长
    CGFloat             _minBufferedDuration;       //
    CGFloat             _maxBufferedDuration;       //最小缓存时长
    BOOL                _buffered;                  //是否在缓存中
    
    BOOL                _savedIdleTimer;
    
    NSDictionary        *_parameters;
}
@property (readwrite) BOOL playing;                 //播放状态判断
@property (readwrite) BOOL decoding;                //解码状态判断
@property (readwrite, strong) ArtworkFrame *artworkFrame;

@end


@implementation MovieViewController

#pragma mark - init life cycle
//历史
+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

//状态栏
- (BOOL)prefersStatusBarHidden { return YES; }

//
+ (instancetype)playerUrl:(NSString *)url paramters:(NSDictionary *)param
{
    //启用音频
    id<AudioManagerDelegate> audioManager = [AudioManager audioManager];
    [audioManager activateAudioSession];
    
    return [[MovieViewController alloc] initWithContentPath:url parameters:param];
}

- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _moviePosition = 0;
//        self.wantsFullScreenLayout = YES;
        
        _parameters = parameters;
        
        if (!path || path.length <= 0) {
            NSLog(@"stream url error!");
        }
        __weak MovieViewController *weakSelf = self;
        //初始化解码器类
        MovieDecoder *decoder = [[MovieDecoder alloc] init];
        decoder.decoderDelegate = self;
        decoder.interruptCallback = ^BOOL(){ //中断回调
            __strong MovieViewController *strongSelf = weakSelf;
            //
            return strongSelf ? [strongSelf interruptDecoder] : YES;
        };
        
        //开启异步线程来处理流解码
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSError *error = nil;
            //
            [decoder openFile:path error:&error];
            //
            __strong MovieViewController *strongSelf = weakSelf;
            if (strongSelf) {
                //返回主线程
                dispatch_sync(dispatch_get_main_queue(), ^{
                    //
                    [strongSelf setMovieDecoder:decoder withError:error];
                });
            }
        });
    }
    return self;
}

- (void)viewDidAppear:(BOOL)animated
{
     LoggerStream(1, @"viewDidAppear");
    
    [super viewDidAppear:animated];
    
    if (self.presentingViewController)
        [self fullscreenMode:YES];
    
    if (_infoMode)
        [self showInfoView:NO animated:NO];
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
    [self showHUD: YES];
    
    if (_decoder) {
        
        [self restorePlay];
        
    } else {
        
        [_activityIndicatorView startAnimating];
    }
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super viewWillDisappear:animated];
    
    [_activityIndicatorView stopAnimating];
    
    if (_decoder) {
        
        [self pause];
        
        if (_moviePosition == 0 || _decoder.isEOF)
            [gHistory removeObjectForKey:_decoder.path];
        else if (!_decoder.isNetwork)
            [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
                        forKey:_decoder.path];
    }
    
    if (_fullscreen)
        [self fullscreenMode:NO];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
    
    [_activityIndicatorView stopAnimating];
    _buffered = NO;
    _interrupted = YES;
    
    LoggerStream(1, @"viewWillDisappear %@", self);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    [self showHUD:YES];
    [self pause];
    
    LoggerStream(1, @"applicationWillResignActive");
}

- (void) dealloc
{
    [self pause];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_dispatchQueue) {
        // Not needed as of ARC.
//        dispatch_release(_dispatchQueue);
        _dispatchQueue = NULL;
    }
    
    LoggerStream(1, @"%@ dealloc", self);
}

//加载控件
- (void)loadView
{
    // LoggerStream(1, @"loadView");
    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
    
    self.view = [[UIView alloc] initWithFrame:bounds];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.tintColor = [UIColor blackColor];
    //
    _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhiteLarge];
    _activityIndicatorView.center = self.view.center;
    _activityIndicatorView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_activityIndicatorView];
    
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    
#ifdef DEBUG
    _messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20,40,width-40,40)];
    _messageLabel.backgroundColor = [UIColor clearColor];
    _messageLabel.textColor = [UIColor redColor];
    _messageLabel.hidden = YES;
    _messageLabel.font = [UIFont systemFontOfSize:14];
    _messageLabel.numberOfLines = 2;
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_messageLabel];
#endif
    
    CGFloat topH = 50;
    CGFloat botH = 50;
    
    _topHUD    = [[UIView alloc] initWithFrame:CGRectMake(0,0,0,0)];
    _topBar    = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, width, topH)];
    _bottomBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, height-botH, width, botH)];
    _bottomBar.tintColor = [UIColor blackColor];
    
    _topHUD.frame = CGRectMake(0,0,width,_topBar.frame.size.height);
    
    _topHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _bottomBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    
    [self.view addSubview:_topBar];
    [self.view addSubview:_topHUD];
    [self.view addSubview:_bottomBar];
    
    // top hud
    
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton.frame = CGRectMake(0, 1, 50, topH);
    _doneButton.backgroundColor = [UIColor clearColor];
    //    _doneButton.backgroundColor = [UIColor redColor];
    [_doneButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_doneButton setTitle:NSLocalizedString(@"done", nil) forState:UIControlStateNormal];
    _doneButton.titleLabel.font = [UIFont systemFontOfSize:18];
    _doneButton.showsTouchWhenHighlighted = YES;
    [_doneButton addTarget:self action:@selector(doneDidTouch:)
          forControlEvents:UIControlEventTouchUpInside];
    //    [_doneButton setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
    
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(46, 1, 50, topH)];
    _progressLabel.backgroundColor = [UIColor clearColor];
    _progressLabel.opaque = NO;
    _progressLabel.adjustsFontSizeToFitWidth = NO;
    _progressLabel.textAlignment = NSTextAlignmentRight;
    _progressLabel.textColor = [UIColor blackColor];
    _progressLabel.text = @"";
    _progressLabel.font = [UIFont systemFontOfSize:12];
    
    _progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(100, 2, width-197, topH)];
    _progressSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressSlider.continuous = NO;
    _progressSlider.value = 0;
    //    [_progressSlider setThumbImage:[UIImage imageNamed:@"kxmovie.bundle/sliderthumb"]
    //                          forState:UIControlStateNormal];
    
    _leftLabel = [[UILabel alloc] initWithFrame:CGRectMake(width-92, 1, 60, topH)];
    _leftLabel.backgroundColor = [UIColor clearColor];
    _leftLabel.opaque = NO;
    _leftLabel.adjustsFontSizeToFitWidth = NO;
    _leftLabel.textAlignment = NSTextAlignmentLeft;
    _leftLabel.textColor = [UIColor blackColor];
    _leftLabel.text = @"";
    _leftLabel.font = [UIFont systemFontOfSize:12];
    _leftLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
    _infoButton = [UIButton buttonWithType:UIButtonTypeInfoDark];
    _infoButton.frame = CGRectMake(width-31, (topH-20)/2+1, 20, 20);
    _infoButton.showsTouchWhenHighlighted = YES;
    _infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_infoButton addTarget:self action:@selector(infoDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    [_topHUD addSubview:_doneButton];
    [_topHUD addSubview:_progressLabel];
    [_topHUD addSubview:_progressSlider];
    [_topHUD addSubview:_leftLabel];
    [_topHUD addSubview:_infoButton];
    
    // bottom hud
    
    _spaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                               target:nil
                                                               action:nil];
    
    _fixedSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                    target:nil
                                                                    action:nil];
    _fixedSpaceItem.width = 30;
    
    _rewindBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind
                                                               target:self
                                                               action:@selector(rewindDidTouch:)];
    
    _playBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                             target:self
                                                             action:@selector(playDidTouch:)];
    _playBtn.width = 50;
    
    _pauseBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause
                                                              target:self
                                                              action:@selector(playDidTouch:)];
    _pauseBtn.width = 50;
    
    _fforwardBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFastForward
                                                                 target:self
                                                                 action:@selector(forwardDidTouch:)];
    
    [self updateBottomBar];
    
    if (_decoder) {
        [self setupPresentView];
    } else {
        _progressLabel.hidden = YES;
        _progressSlider.hidden = YES;
        _leftLabel.hidden = YES;
        _infoButton.hidden = YES;
    }
}


#pragma mark - private methods
//
- (void)setMovieDecoder:(MovieDecoder *)decoder withError:(NSError *)error
{
    LoggerStream(2, @"setMovieDecoder");
    
    if (!error && decoder) {
        _decoder        = decoder;
        //创建队列
        _dispatchQueue  = dispatch_queue_create("SFMovie", DISPATCH_QUEUE_SERIAL);
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
        if (_parameters.count) {
            id val;
            
            val = [_parameters valueForKey:KMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey:KMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey:KMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        if (self.isViewLoaded) {
            //
            [self setupPresentView];
            
            _progressLabel.hidden   = NO;
            _progressSlider.hidden  = NO;
            _leftLabel.hidden       = NO;
            _infoButton.hidden      = NO;
            
            if (_activityIndicatorView.isAnimating) {
                [_activityIndicatorView stopAnimating];
                // if (self.view.window)
                [self restorePlay];
            }
        }
        
    } else {
        //
        if (self.isViewLoaded && self.view.window) {
            [_activityIndicatorView stopAnimating];
            if (!_interrupted)
                [self handleDecoderMovieError: error];
        }
    }
}
//
- (UIView *)frameView
{
    return _glView ? _glView : _imageView;
}
//用户触发
- (void) setupUserInteraction
{
    UIView *view = [self frameView];
    view.userInteractionEnabled = YES;
    //sigle
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapGestureRecognizer.numberOfTapsRequired = 1;
    //double
    _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    //双击失败才触发单击
    [_tapGestureRecognizer requireGestureRecognizerToFail: _doubleTapGestureRecognizer];
    
    [view addGestureRecognizer:_doubleTapGestureRecognizer];
    [view addGestureRecognizer:_tapGestureRecognizer];
    
    //    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    //    _panGestureRecognizer.enabled = NO;
    //
    //    [view addGestureRecognizer:_panGestureRecognizer];
}
//恢复播放
- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}
//
- (void) setupPresentView
{
    CGRect bounds = self.view.bounds;
    //创建opengles view
    if (_decoder.validVideo) {
        _glView = [[MovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    }
    
    //创建imageview
    if (!_glView) {
        LoggerVideo(0, @"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:VideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
        _imageView.backgroundColor = [UIColor blackColor];
    }
    
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    //add view
    [self.view insertSubview:frameView atIndex:0];
    
    if (_decoder.validVideo) {
        //设置手势
        [self setupUserInteraction];
    } else {
        //
        _imageView.image = [UIImage imageNamed:@"kxmovie.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    self.view.backgroundColor = [UIColor clearColor];
    
    //left time label and progress slider
    if (_decoder.duration == MAXFLOAT) {
        _leftLabel.text = @"\u221E"; // infinity
        _leftLabel.font = [UIFont systemFontOfSize:14];
        
        CGRect frame;
        
        frame = _leftLabel.frame;
        frame.origin.x += 40;
        frame.size.width -= 40;
        _leftLabel.frame = frame;
        
        frame =_progressSlider.frame;
        frame.size.width += 40;
        _progressSlider.frame = frame;
    } else {
        [_progressSlider addTarget:self
                            action:@selector(progressDidChange:)
                  forControlEvents:UIControlEventValueChanged];
    }
    
    CGSize size = self.view.bounds.size;
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
        
        [self.view addSubview:_subtitlesLabel];
    }
    
    _bitrateLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, size.height-80, 40, 20)];
    _bitrateLabel.backgroundColor = [UIColor clearColor];
    _bitrateLabel.textAlignment = NSTextAlignmentCenter;
    _bitrateLabel.textColor = [UIColor whiteColor];
    _bitrateLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:_bitrateLabel];
}

//更新位置
- (void)updatePosition:(CGFloat) position playMode:(BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak MovieViewController *weakSelf = self;
    //开启异步线程
    dispatch_async(_dispatchQueue, ^{
        if (playMode) { //播放
            {
                __strong MovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                //
                [strongSelf setDecoderPosition: position];
            }
            
            //返回主线程
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong MovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                }
            });
        } else { //未播放
            {
                __strong MovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            //返回主线程
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong MovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf enableUpdateHUD];
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    [strongSelf updateHUD];
                }
            });
        }        
    });
}

//
- (BOOL)decodeFrames
{
    NSArray *frames = nil;
    //读取解码帧
    if (_decoder.validVideo || _decoder.validAudio) {
        frames = [_decoder decodeFrames:0];
        [self showBitrate];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

//同步取帧
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
- (void) asyncDecodeFrames
{
    if (self.decoding)
        return;
    
    __weak MovieViewController *weakSelf = self;
    __weak MovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    //开启异步线程
    dispatch_async(_dispatchQueue, ^{
        {
            __strong MovieViewController *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good) {
            good = NO;
            //线程池
            @autoreleasepool {
                __strong MovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    //decode
                    NSArray *frames = [decoder decodeFrames:duration];
                    [self showBitrate];
                    if (frames.count) {
                        __strong MovieViewController *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames]; //add
                    }
                }
            }
        }
        
        {
            __strong MovieViewController *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

//
- (CGFloat)presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        VideoFrame *frame;
        
        @synchronized(_videoFrames) {
            if (_videoFrames.count > 0) {
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {
        //interval = _bufferedDuration * 0.5;
        
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

//将帧添加到view
- (CGFloat)presentVideoFrame:(VideoFrame *) frame
{
    if (_glView) {
        [_glView render:frame];
    } else {
        VideoFrameRGB *rgbFrame = (VideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
    
    return frame.duration;
}

//将字幕显示到subtitle label上
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
                
                CGSize viewSize = self.view.bounds.size;
                CGSize size = [ms sizeWithFont:_subtitlesLabel.font
                             constrainedToSize:CGSizeMake(viewSize.width, viewSize.height * 0.5)
                                 lineBreakMode:NSLineBreakByTruncatingTail];
                _subtitlesLabel.text = ms;
                _subtitlesLabel.frame = CGRectMake(0, viewSize.height - size.height - 10,
                                                   viewSize.width, size.height);
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

//
- (void)enableAudio:(BOOL) on
{
    id<AudioManagerDelegate> audioManager = [AudioManager audioManager];
    //
    if (on && _decoder.validAudio) { //开启音频
        //音频输出回调
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
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

//提示解码错误提示
- (void)handleDecoderMovieError:(NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
}

//中断解码
- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

//
- (void)showInfoView:(BOOL)showInfo animated:(BOOL)animated
{
    if (!_tableView)
        [self createTableView];
    
    [self pause];
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    
    if (showInfo) {
        _tableView.hidden = NO;
        
        if (animated) {
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
                             }
                             completion:nil];
        } else {
            _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
        }
        
    } else {
        if (animated) {
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
                             }
                             completion:^(BOOL f){
                                 if (f) {
                                     _tableView.hidden = YES;
                                 }
                             }];
        } else {
            _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
            _tableView.hidden = YES;
        }
    }
    
    _infoMode = showInfo;
}

//
- (void)createTableView
{
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.hidden = YES;
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
    
    [self.view addSubview:_tableView];
}

- (void) updatePlayButton
{
    [self updateBottomBar];
}

- (void) updateBottomBar
{
    UIBarButtonItem *playPauseBtn = self.playing ? _pauseBtn : _playBtn;
    [_bottomBar setItems:@[_spaceItem, _rewindBtn, _fixedSpaceItem, playPauseBtn,
                           _fixedSpaceItem, _fforwardBtn, _spaceItem] animated:NO];
}

- (void) fullscreenMode: (BOOL) on
{
    _fullscreen = on;
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:on withAnimation:UIStatusBarAnimationNone];
    // if (!self.presentingViewController) {
    //[self.navigationController setNavigationBarHidden:on animated:YES];
    //[self.tabBarController setTabBarHidden:on animated:YES];
    // }
}

- (void)showBitrate {
    int bitrate = [_decoder.info[@"bitrate"] intValue];
    _bitrateLabel.text = [NSString stringWithFormat:@"%d kb/s", bitrate/1000];
}

#pragma mark - public methods
- (void) setMoviePosition: (CGFloat) position
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

-(void) play
{
    if (self.playing)
        return;
    
    if (!_decoder.validVideo && !_decoder.validAudio) {
        return;
    }
    
    if (_interrupted) //如果中断
        return;
    
    self.playing = YES;
    _interrupted = NO;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;
    
#ifdef DEBUG
    _debugStartTime = -1;
#endif
    
    [self asyncDecodeFrames];   //
    [self updatePlayButton];    //
    
    //开启时间计时器
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    if (_decoder.validAudio)
        [self enableAudio:YES];
    
    LoggerStream(1, @"play movie");
}

- (void) pause
{
    if (!self.playing)
        return;
    
    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    [self updatePlayButton];
    LoggerStream(1, @"pause movie");
}

//
- (void) tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        _tickCorrectionTime = 0;
        _buffered = NO;
        [_activityIndicatorView stopAnimating];
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        const NSUInteger leftFrames = (_decoder.validVideo ? _videoFrames.count : 0) + (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) {
            if (_decoder.isEOF) {
                [self pause];
                [self updateHUD];
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) {
                _buffered = YES;
                [_activityIndicatorView startAnimating];
            }
        }
        
        if (!leftFrames || !(_bufferedDuration > _minBufferedDuration)) {
            //
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
        [self updateHUD];
    }
}

//返回当前时间
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
    
    //if ((_tickCounter % 200) == 0)
    //    LoggerStream(1, @"tick correction %.4f", correction);
    
    if (correction > 1.f || correction < -1.f) {
        LoggerStream(1, @"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

#pragma mark - actions
- (void)handleTap:(UITapGestureRecognizer *) sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (sender == _tapGestureRecognizer) {
            [self showHUD: _hiddenHUD];
            
        } else if (sender == _doubleTapGestureRecognizer) {
            UIView *frameView = [self frameView];
            
            if (frameView.contentMode == UIViewContentModeScaleAspectFit)
                frameView.contentMode = UIViewContentModeScaleAspectFill;
            else
                frameView.contentMode = UIViewContentModeScaleAspectFit;
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *) sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        const CGPoint vt = [sender velocityInView:self.view];
        const CGPoint pt = [sender translationInView:self.view];
        const CGFloat sp = MAX(0.1, log10(fabs(vt.x)) - 1.0);
        const CGFloat sc = fabs(pt.x) * 0.33 * sp;
        if (sc > 10) {
            
            const CGFloat ff = pt.x > 0 ? 1.0 : -1.0;
            [self setMoviePosition: _moviePosition + ff * MIN(sc, 600.0)];
        }
        //LoggerStream(2, @"pan %.2f %.2f %.2f sec", pt.x, vt.x, sc);
    }
}

//返回
- (void)doneDidTouch:(id) sender
{
    if (self.presentingViewController || !self.navigationController)
        [self dismissViewControllerAnimated:YES completion:nil];
    else
        [self.navigationController popViewControllerAnimated:YES];
}

//显示信息
- (void)infoDidTouch:(id) sender
{
    [self showInfoView: !_infoMode animated:YES];
}

//播放/暂停
- (void)playDidTouch:(id) sender
{
    if (self.playing)
        [self pause];
    else
        [self play];
}

//快进
- (void)forwardDidTouch: (id) sender
{
    [self setMoviePosition: _moviePosition + 10];
}

//快退
- (void)rewindDidTouch: (id) sender
{
    [self setMoviePosition: _moviePosition - 10];
}

//progress change value
- (void)progressDidChange: (id) sender
{
    NSAssert(_decoder.duration != MAXFLOAT, @"bugcheck");
    UISlider *slider = sender;
    [self setMoviePosition:slider.value * _decoder.duration];
}


#pragma mark - HUD
- (void) enableUpdateHUD
{
    _disableUpdateHUD = NO;
}

- (void) updateHUD
{
    if (_disableUpdateHUD)
        return;
    
    const CGFloat duration = _decoder.duration;
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if (_progressSlider.state == UIControlStateNormal)
        _progressSlider.value = position / duration;
    _progressLabel.text = formatTimeInterval(position, NO);
    
    if (_decoder.duration != MAXFLOAT)
        _leftLabel.text = formatTimeInterval(duration - position, YES);
    
#ifdef DEBUG
    const NSTimeInterval timeSinceStart = [NSDate timeIntervalSinceReferenceDate] - _debugStartTime;
    NSString *subinfo = _decoder.validSubtitles ? [NSString stringWithFormat: @" %lu",(unsigned long)_subtitles.count] : @"";
    
    NSString *audioStatus;
    
    if (_debugAudioStatus) {
        
        if (NSOrderedAscending == [_debugAudioStatusTS compare: [NSDate dateWithTimeIntervalSinceNow:-0.5]]) {
            _debugAudioStatus = 0;
        }
    }
    
    if      (_debugAudioStatus == 1) audioStatus = @"\n(audio outrun)";
    else if (_debugAudioStatus == 2) audioStatus = @"\n(audio lags)";
    else if (_debugAudioStatus == 3) audioStatus = @"\n(audio silence)";
    else audioStatus = @"";
    
    _messageLabel.text = [NSString stringWithFormat:@"%lu %lu%@ %c - %@ %@ %@\n%@",
                          (unsigned long)_videoFrames.count,
                          (unsigned long)_audioFrames.count,
                          subinfo,
                          self.decoding ? 'D' : ' ',
                          formatTimeInterval(timeSinceStart, NO),
                          //timeSinceStart > _moviePosition + 0.5 ? @" (lags)" : @"",
                          _decoder.isEOF ? @"- END" : @"",
                          audioStatus,
                          _buffered ? [NSString stringWithFormat:@"buffering %.1f%%", _bufferedDuration / _minBufferedDuration * 100] : @""];
#endif
}

- (void) showHUD: (BOOL) show
{
    _hiddenHUD = !show;
    _panGestureRecognizer.enabled = _hiddenHUD;
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:_hiddenHUD];
    
    [UIView animateWithDuration:0.2
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                     animations:^{
                         
                         CGFloat alpha = _hiddenHUD ? 0 : 1;
                         _topBar.alpha = alpha;
                         _topHUD.alpha = alpha;
                         _bottomBar.alpha = alpha;
                     }
                     completion:nil];
    
}

#pragma mark - property setter/getter
- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void) setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

#pragma mark - moviedecorder delegate
- (void)movieDecoderDidOccurError:(NSError *)error {
    
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return MovieInfoSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case MovieInfoSectionGeneral:
            return NSLocalizedString(@"General", nil);
        case MovieInfoSectionMetadata:
            return NSLocalizedString(@"Metadata", nil);
        case MovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count ? NSLocalizedString(@"Video", nil) : nil;
        }
        case MovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count ?  NSLocalizedString(@"Audio", nil) : nil;
        }
        case MovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? NSLocalizedString(@"Subtitles", nil) : nil;
        }
    }
    return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case MovieInfoSectionGeneral:
            return MovieInfoGeneralCount;
            
        case MovieInfoSectionMetadata: {
            NSDictionary *d = [_decoder.info valueForKey:@"metadata"];
            return d.count;
        }
            
        case MovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count;
        }
            
        case MovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count;
        }
            
        case MovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? a.count + 1 : 0;
        }
            
        default:
            return 0;
    }
}

- (id) mkCell: (NSString *) cellIdentifier
    withStyle: (UITableViewCellStyle) style
{
    UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    
    if (indexPath.section == MovieInfoSectionGeneral) {
        
        if (indexPath.row == MovieInfoGeneralBitrate) {
            
            int bitrate = [_decoder.info[@"bitrate"] intValue];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Bitrate", nil);
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d kb/s",bitrate / 1000];
            
        } else if (indexPath.row == MovieInfoGeneralFormat) {
            
            NSString *format = _decoder.info[@"format"];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Format", nil);
            cell.detailTextLabel.text = format ? format : @"-";
        }
        
    } else if (indexPath.section == MovieInfoSectionMetadata) {
        
        NSDictionary *d = _decoder.info[@"metadata"];
        NSString *key = d.allKeys[indexPath.row];
        cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = key.capitalizedString;
        cell.detailTextLabel.text = [d valueForKey:key];
        
    } else if (indexPath.section == MovieInfoSectionVideo) {
        
        NSArray *a = _decoder.info[@"video"];
        cell = [self mkCell:@"VideoCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;
        
    } else if (indexPath.section == MovieInfoSectionAudio) {
        
        NSArray *a = _decoder.info[@"audio"];
        cell = [self mkCell:@"AudioCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;
        BOOL selected = _decoder.selectedAudioStream == indexPath.row;
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        
    } else if (indexPath.section == MovieInfoSectionSubtitles) {
        
        NSArray *a = _decoder.info[@"subtitles"];
        
        cell = [self mkCell:@"SubtitleCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 1;
        
        if (indexPath.row) {
            cell.textLabel.text = a[indexPath.row - 1];
        } else {
            cell.textLabel.text = NSLocalizedString(@"Disable", nil);
        }
        
        const BOOL selected = _decoder.selectedSubtitleStream == (indexPath.row - 1);
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == MovieInfoSectionAudio) {
        
        NSInteger selected = _decoder.selectedAudioStream;
        
        if (selected != indexPath.row) {
            
            _decoder.selectedAudioStream = indexPath.row;
            NSInteger now = _decoder.selectedAudioStream;
            
            if (now == indexPath.row) {
                
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected inSection:MovieInfoSectionAudio];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
        }
        
    } else if (indexPath.section == MovieInfoSectionSubtitles) {
        
        NSInteger selected = _decoder.selectedSubtitleStream;
        
        if (selected != (indexPath.row - 1)) {
            
            _decoder.selectedSubtitleStream = indexPath.row - 1;
            NSInteger now = _decoder.selectedSubtitleStream;
            
            if (now == (indexPath.row - 1)) {
                
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected + 1 inSection:MovieInfoSectionSubtitles];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
            
            // clear subtitles
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
            @synchronized(_subtitles) {
                [_subtitles removeAllObjects];
            }
        }
    }
}

@end
