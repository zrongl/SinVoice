//
//  SinPlayer.h
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "SinVoice.h"

typedef struct {
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef mQueue;
    AudioQueueBufferRef mBuffers[kNumberBuffers];
    SInt64 mCurrentPacket;
    UInt32 mNumPacketsToRead;
    UInt32 bufferByteSize;
    bool mIsRunning;
    char *mCode;
    UInt32 mCodeLength;
    float mTheta;
} AQPlayState;

@interface SinPlayer : NSObject

@property (nonatomic, assign) AQPlayState playState;

- (void)play:(NSString *)message;
- (void)stop;

@end
