# SFPlayer
描述
  该播放器采用ffmpeg+opengles的方式实现
功能
  1、流解析，转换成相应的YUV格式的帧和RGB帧
  2、通过OpenGL ES 2.0进行视频渲染
  3、播放/暂停控制
  4、快进/快退控制
  5、快放/慢放
  6、返回多音轨列表并可以选择音轨
  7、返回多字幕列表并可以选择字幕
  8、设置音量
  9、重新播放
  10、记录当前播放进度
  11、返回播放帧率
  12、设置最小缓冲时长（单位s）
  13、设置屏幕亮度、视频的饱和度
回调方法
  1、将要加载视频
  - (void)moviePlayerWillLoad:(MoviePlayerController *)playerController;
  2、加载完成
  - (void)moviePlayerDidLoad:(MoviePlayerController *)playerController error:(NSError *)error;
  3、播放状态改变
  - (void)moviePlayerDidStateChange:(MoviePlayerController *)playerController;
  4、实时返回当前播放时间
  - (void)moviePlayerDidCurrentTimeChange:(MoviePlayerController *)playerController  position:(NSTimeInterval)position;
  5、缓冲进度
  - (void)moviePlayerDidBufferingProgressChange:(MoviePlayerController *)playerController progress:(double)progress;
  6、帧率改变
  - (void)moviePlayerDidFramerateChange:(MoviePlayerController *)playerController framerate:(NSInteger)framerate;
  7、全屏/非全屏
  - (void)moviePlayerDidEnterFullscreenMode:(MoviePlayerController *)controller;
  - (void)moviePlayerDidExitFullscreenMode:(MoviePlayerController *)controller;
