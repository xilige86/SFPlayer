//
//  Logger.h
//  SFPlayer
//
//  Created by cdsf on 16/4/13.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#ifndef Logger_h
#define Logger_h

//#define USE_NSLOGGER


#ifdef DEBUG
#ifdef USE_NSLOGGER

#    import "NSLogger.h"
#    define LoggerStream(level, ...)   LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Stream", level, __VA_ARGS__)
#    define LoggerVideo(level, ...)    LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Video",  level, __VA_ARGS__)
#    define LoggerAudio(level, ...)    LogMessageF(__FILE__, __LINE__, __FUNCTION__, @"Audio",  level, __VA_ARGS__)

#else

#    define LoggerStream(level, ...)   NSLog(__VA_ARGS__)
#    define LoggerVideo(level, ...)    NSLog(__VA_ARGS__)
#    define LoggerAudio(level, ...)    NSLog(__VA_ARGS__)

#endif
#else

#    define LoggerStream(...)          while(0) {}
#    define LoggerVideo(...)           while(0) {}
#    define LoggerAudio(...)           while(0) {}

#endif

#endif /* Logger_h */
