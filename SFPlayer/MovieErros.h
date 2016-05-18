//
//  MovieErros.h
//  SFPlayer
//
//  Created by cdsf on 16/4/18.
//  Copyright © 2016年 cdsf. All rights reserved.
//

typedef enum {
    MovieErrorNone,
    MovieErrorOpenFile,
    MovieErrorStreamInfoNotFound,
    MovieErrorStreamNotFound,
    MovieErrorCodecNotFound,
    MovieErrorOpenCodec,
    MovieErrorAllocateFrame,    //初始化frame错误
    MovieErrorSetupScaler,      //
    MovieErrorReSampler,        //取样器错误
    MovieErrorUnsupported
} MovieError;
