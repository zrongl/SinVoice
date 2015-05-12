//
//  SinRecorder.h
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
    UInt32 bufferByteSize;
    SInt64 mCurrentPacket;
    bool mIsRunning;
    __unsafe_unretained id mSelf;
} AQRecordState;

@protocol SinRecorderDelegate <NSObject>
@optional

- (void)updateRecord:(NSString *)text state:(NSString *)state;

@end

@interface SinRecorder : NSObject
@property (nonatomic, assign) AQRecordState recordState;
@property (nonatomic, assign) id<SinRecorderDelegate>delegate;

- (void)start;
- (void)stop;
- (void)process:(short *)samples length:(long)length;

@end
