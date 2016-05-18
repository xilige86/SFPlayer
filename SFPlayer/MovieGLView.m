//
//  MovieGLView.m
//  SFPlayer
//
//  Created by cdsf on 16/4/14.
//  Copyright © 2016年 cdsf. All rights reserved.
//

#import "MovieGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "MovieDecoder.h"


#pragma mark - shaders

#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

//顶点着色
NSString *const vertexShaderString = SHADER_STRING
(
     // attribute修饰符用于声明通过OpenGL ES应用程序传递到顶点着色器中的变量值
     attribute vec4 position;
     attribute vec2 texcoord;
     uniform mat4 modelViewProjectionMatrix;    //模型视图投影矩阵
     //varying提供顶点着色器
     varying vec2 v_texcoord;                   //向片段着色其传递的参数
     
     void main()
     {
         gl_Position = modelViewProjectionMatrix * position;
         v_texcoord = texcoord.xy;
     }
 );

//rgb着色
NSString *const rgbFragmentShaderString = SHADER_STRING
(
     varying highp vec2 v_texcoord;
     uniform sampler2D s_texture;
     
     void main()
     {
         gl_FragColor = texture2D(s_texture, v_texcoord);
     }
 );

//YUV着色
//NSString *const yuvFragmentShaderString = SHADER_STRING
//(
//     varying highp vec2 v_texcoord;
//     uniform sampler2D s_texture_y;
//     uniform sampler2D s_texture_u;
//     uniform sampler2D s_texture_v;
//     uniform lowp float saturation;
// 
//     void main()
//     {
//         highp float y = texture2D(s_texture_y, v_texcoord).r;
//         highp float u = texture2D(s_texture_u, v_texcoord).r - 0.5;
//         highp float v = texture2D(s_texture_v, v_texcoord).r - 0.5;
//
//         highp float r = y +             1.402 * v;
//         highp float g = y - 0.344 * u - 0.714 * v;
//         highp float b = y + 1.772 * u;
//         
//         gl_FragColor = vec4(r,g,b,1.0);
//     }
// );

NSString *const yuvFragmentShaderString = SHADER_STRING
(
 varying highp vec2 v_texcoord;
 
 uniform sampler2D s_texture_y;
 uniform sampler2D s_texture_u;
 uniform sampler2D s_texture_v;
 
 uniform highp float saturation;
 
 void main()
 {
     mediump vec3 yuv;
     highp vec3 rgb;
     
     yuv.x = texture2D(s_texture_y, v_texcoord).r;
     yuv.y = texture2D(s_texture_u, v_texcoord).r - 0.5;
     yuv.z = texture2D(s_texture_v, v_texcoord).r - 0.5;
     
     rgb = mat3( 1,       1,         1,
                0,       -0.39465,  2.03211,
                1.13983, -0.58060,  0) * yuv;
     
     lowp vec4 textureColor = vec4(rgb,1);
     //坐标来获取颜色信息
     lowp float luminance = dot(textureColor.rgb, rgb);
     //
     lowp vec3 greyScaleColor = vec3(luminance);
     //
     gl_FragColor = vec4(mix(greyScaleColor, textureColor.rgb, saturation), textureColor.w);
 }
 );

//
static BOOL validateProgram(GLuint prog)
{
    GLint status;
    
    glValidateProgram(prog);
    
#ifdef DEBUG
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        LoggerVideo(1, @"Program validate log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == GL_FALSE) {
        LoggerVideo(0, @"Failed to validate program %d", prog);
        return NO;
    }
    
    return YES;
}

//
static GLuint compileShader(GLenum type, NSString *shaderString)
{
    GLint status;
    const GLchar *sources = (GLchar *)shaderString.UTF8String;
    
    GLuint shader = glCreateShader(type);
    if (shader == 0 || shader == GL_INVALID_ENUM) {
        LoggerVideo(0, @"Failed to create shader %d", type);
        return 0;
    }
    
    glShaderSource(shader, 1, &sources, NULL);
    glCompileShader(shader);
    
#ifdef DEBUG
    GLint logLength;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
        LoggerVideo(1, @"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        glDeleteShader(shader);
        LoggerVideo(0, @"Failed to compile shader:\n");
        return 0;
    }
    
    return shader;
}

static void mat4f_LoadOrtho(float left, float right, float bottom, float top, float near, float far, float* mout)
{
    float r_l = right - left;
    float t_b = top - bottom;
    float f_n = far - near;
    float tx = - (right + left) / (right - left);
    float ty = - (top + bottom) / (top - bottom);
    float tz = - (far + near) / (far - near);
    
    mout[0] = 2.0f / r_l;
    mout[1] = 0.0f;
    mout[2] = 0.0f;
    mout[3] = 0.0f;
    
    mout[4] = 0.0f;
    mout[5] = 2.0f / t_b;
    mout[6] = 0.0f;
    mout[7] = 0.0f;
    
    mout[8] = 0.0f;
    mout[9] = 0.0f;
    mout[10] = -2.0f / f_n;
    mout[11] = 0.0f;
    
    mout[12] = tx;
    mout[13] = ty;
    mout[14] = tz;
    mout[15] = 1.0f;
}


#pragma mark - frame renderers

@protocol MovieGLRenderDelegate <NSObject>

- (BOOL)isValid;
- (NSString *)fragmentShader;
- (void)resolveUniforms:(GLuint)program;
- (void)setFrame: (VideoFrame *)frame;
- (BOOL)prepareRender:(GLfloat)val;

@end


@interface MovieGLRender_RGB : NSObject<MovieGLRenderDelegate> {
    GLint _uniformSampler;  //采样器
    GLuint _texture;        //纹理
}

@end

@implementation MovieGLRender_RGB

- (BOOL)isValid
{
    return (_texture != 0);
}

- (NSString *)fragmentShader
{
    return rgbFragmentShaderString;
}

- (void)resolveUniforms:(GLuint)program
{
    _uniformSampler = glGetUniformLocation(program, "s_texture");
}

- (void)setFrame:(VideoFrame *)frame
{
    VideoFrameRGB *rgbFrame = (VideoFrameRGB *)frame;
    
    assert(rgbFrame.rgb.length == rgbFrame.width * rgbFrame.height * 3);
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    if (0 == _texture)
        glGenTextures(1, &_texture);
    
    glBindTexture(GL_TEXTURE_2D, _texture);
    
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGB,
                 (int32_t)frame.width,
                 (int32_t)frame.height,
                 0,
                 GL_RGB,
                 GL_UNSIGNED_BYTE,
                 rgbFrame.rgb.bytes);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

//
- (BOOL)prepareRender:(GLfloat)val
{
    if (_texture == 0)
        return NO;
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glUniform1i(_uniformSampler, 0);
    
    return YES;
}

- (void)dealloc
{
    if (_texture) {
        glDeleteTextures(1, &_texture);
        _texture = 0;
    }
}

@end


@interface MovieGLRender_YUV : NSObject<MovieGLRenderDelegate> {
    GLint _uniformSamplers[3];
    GLuint _textures[3];
    GLfloat _saturation;
}

@end

@implementation MovieGLRender_YUV

- (BOOL) isValid
{
    return (_textures[0] != 0);
}

- (NSString *) fragmentShader
{
    return yuvFragmentShaderString;
}

- (void) resolveUniforms: (GLuint) program
{
    _uniformSamplers[0] = glGetUniformLocation(program, "s_texture_y");
    _uniformSamplers[1] = glGetUniformLocation(program, "s_texture_u");
    _uniformSamplers[2] = glGetUniformLocation(program, "s_texture_v");
    _saturation = glGetUniformLocation(program, "saturation");
}

- (void)setFrame:(VideoFrame *) frame
{
    VideoFrameYUV *yuvFrame = (VideoFrameYUV *)frame;
    
    assert(yuvFrame.luma.length == yuvFrame.width * yuvFrame.height);
    assert(yuvFrame.chromaB.length == (yuvFrame.width * yuvFrame.height) / 4);
    assert(yuvFrame.chromaR.length == (yuvFrame.width * yuvFrame.height) / 4);
    
    const NSUInteger frameWidth = frame.width;
    const NSUInteger frameHeight = frame.height;
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    if (0 == _textures[0])
        //用来生成纹理的数量
        glGenTextures(3, _textures);
    
    const UInt8 *pixels[3] = { yuvFrame.luma.bytes, yuvFrame.chromaB.bytes, yuvFrame.chromaR.bytes };
    const NSUInteger widths[3]  = { frameWidth, frameWidth / 2, frameWidth / 2 };
    const NSUInteger heights[3] = { frameHeight, frameHeight / 2, frameHeight / 2 };
    
    for (int i = 0; i < 3; ++i) {
        // YUV数据更新到texture上
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     (int32_t)widths[i],
                     (int32_t)heights[i],
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     pixels[i]);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
}

//Bind YUV texture
- (BOOL) prepareRender:(GLfloat)val
{
    if (_textures[0] == 0)
        return NO;
    
    for (int i = 0; i < 3; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glUniform1i(_uniformSamplers[i], i);
    }
    
    glUniform1f(_saturation, val);
    
    return YES;
}

- (void) dealloc
{
    if (_textures[0])
        glDeleteTextures(3, _textures);
}

@end


#pragma mark - gl view

enum {
    ATTRIBUTE_VERTEX,   //
   	ATTRIBUTE_TEXCOORD,
};


@implementation MovieGLView {
    MovieDecoder    *_decoder;          //
    EAGLContext     *_context;          //
    GLuint          _framebuffer;
    GLuint          _renderbuffer;
    GLint           _backingWidth;
    GLint           _backingHeight;
    GLuint          _program;
    GLint           _uniformMatrix;
    GLfloat         _vertices[8];
    
    id<MovieGLRenderDelegate> _renderer;//代理
}


+(Class)layerClass {
    return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame decoder:(MovieDecoder *)decoder {
    self = [super initWithFrame:frame];
    if (self) {
        _decoder = decoder;
        
        if ([_decoder setupVideoFrameFormat:VideoFrameFormatYUV]) {
            _renderer = [[MovieGLRender_YUV alloc] init];
            LoggerVideo(1, @"OK use YUV GL renderer");
        }else {
            _renderer = [[MovieGLRender_RGB alloc] init];
            LoggerVideo(1, @"OK use RGB GL renderer");
        }
        
        CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        //创建openGL context
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context || ![EAGLContext setCurrentContext:_context]) {
            LoggerVideo(0, @"failed to setup EAGLContext");
            self = nil;
            return nil;
        }
        //
        glGenFramebuffers(1, &_framebuffer);    //生成
        glGenRenderbuffers(1, &_renderbuffer);  //生成
        glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);    //绑定
        glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer); //绑定
        [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];   //保存
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);   //get width
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight); //get height
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);    //
        //
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            
            LoggerVideo(0, @"failed to make complete framebuffer object %x", status);
            self = nil;
            return nil;
        }
        //
        GLenum glError = glGetError();
        if (GL_NO_ERROR != glError) {
            LoggerVideo(0, @"failed to setup GL %x", glError);
            self = nil;
            return nil;
        }
        
        if (![self loadShaders]) {
            self = nil;
            return nil;
        }
        
        _vertices[0] = -1.0f;  // x0
        _vertices[1] = -1.0f;  // y0
        _vertices[2] =  1.0f;  // ..
        _vertices[3] = -1.0f;
        _vertices[4] = -1.0f;
        _vertices[5] =  1.0f;
        _vertices[6] =  1.0f;  // x3
        _vertices[7] =  1.0f;  // y3
        
        LoggerVideo(1, @"OK setup GL");
    }
    return self;
}

- (void)layoutSubviews
{
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        
        LoggerVideo(0, @"failed to make complete framebuffer object %x", status);
        
    } else {
        
        LoggerVideo(1, @"OK setup GL framebuffer %d:%d", _backingWidth, _backingHeight);
    }
    
    [self updateVertices];
    [self render: nil];
}

- (void)setContentMode:(UIViewContentMode)contentMode
{
    [super setContentMode:contentMode];
    [self updateVertices];
    if (_renderer.isValid)
        [self render:nil];
}

- (void)dealloc
{
    _renderer = nil;
    
    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    
    if (_renderbuffer) {
        glDeleteRenderbuffers(1, &_renderbuffer);
        _renderbuffer = 0;
    }
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    _context = nil;
}

#pragma mark - private methods
- (BOOL)loadShaders
{
    BOOL result = NO;
    GLuint vertShader = 0, fragShader = 0;
    
    _program = glCreateProgram();
    //
    vertShader = compileShader(GL_VERTEX_SHADER, vertexShaderString);
    if (!vertShader)
        goto exit;
    //
    fragShader = compileShader(GL_FRAGMENT_SHADER, _renderer.fragmentShader);
    if (!fragShader)
        goto exit;
    
    glAttachShader(_program, vertShader);
    glAttachShader(_program, fragShader);
    glBindAttribLocation(_program, ATTRIBUTE_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIBUTE_TEXCOORD, "texcoord");
    
    glLinkProgram(_program);
    
    GLint status;
    glGetProgramiv(_program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
        LoggerVideo(0, @"Failed to link program %d", _program);
        goto exit;
    }
    
    result = validateProgram(_program);
    
    _uniformMatrix = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    [_renderer resolveUniforms:_program];
    
exit:
    
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);
    
    if (result) {
        LoggerVideo(1, @"OK setup GL programm");
    } else {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    return result;
}

//更新顶点坐标
- (void)updateVertices
{
    const BOOL fit      = (self.contentMode == UIViewContentModeScaleAspectFit);
    const float width   = _decoder.frameWidth;
    const float height  = _decoder.frameHeight;
    const float dH      = (float)_backingHeight / height;
    const float dW      = (float)_backingWidth	  / width;
    const float dd      = fit ? MIN(dH, dW) : MAX(dH, dW);
    const float h       = (height * dd / (float)_backingHeight);
    const float w       = (width  * dd / (float)_backingWidth );
    
    _vertices[0] = - w;
    _vertices[1] = - h;
    _vertices[2] =   w;
    _vertices[3] = - h;
    _vertices[4] = - w;
    _vertices[5] =   h;
    _vertices[6] =   w;
    _vertices[7] =   h;
}

//渲染
- (void)render: (VideoFrame *) frame
{
    static const GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
    [EAGLContext setCurrentContext:_context];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(_program);
    
    if (frame) {
        [_renderer setFrame:frame];
    }
    
    GLfloat h = self.contrast*0.5f;
    if ([_renderer prepareRender:h]) {
        GLfloat modelviewProj[16];
        mat4f_LoadOrtho(-1.0f, 1.0f, -1.0f, 1.0f, -1.0f, 1.0f, modelviewProj);
        glUniformMatrix4fv(_uniformMatrix, 1, GL_FALSE, modelviewProj);
        //绘制图像
        glVertexAttribPointer(ATTRIBUTE_VERTEX, 2, GL_FLOAT, 0, 0, _vertices);
        glEnableVertexAttribArray(ATTRIBUTE_VERTEX);
        glVertexAttribPointer(ATTRIBUTE_TEXCOORD, 2, GL_FLOAT, 0, 0, texCoords);
        glEnableVertexAttribArray(ATTRIBUTE_TEXCOORD);
        
#if 0
        if (!validateProgram(_program))
        {
            LoggerVideo(0, @"Failed to validate program");
            return;
        }
#endif
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    //在屏幕上显示出来
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

@end

