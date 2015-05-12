//
//  SinRecorder.m
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#import "SinRecorder.h"


static int indexArray[] = { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 6, -1, -1, -1, -1, 5, -1, -1, -1, 4, -1, -1, 3, -1, -1, 2, -1, -1, 1, -1, -1, 0 };

#define STEP1       1
#define STEP2       2
#define STATE_START 1
#define STATE_STOP  2

#define MAX_SAMPLING_POINT_COUNT    31
#define MIN_REG_CIRCLE_COUNT        10
#define INDEX(x)                    indexArray[x]

void HandleInputBuffer(void * inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp * inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription * inPacketDesc) {
    AQRecordState * pRecordState = (AQRecordState *)inUserData;
    
    if (inNumPackets == 0 && pRecordState->mDataFormat.mBytesPerPacket != 0) {
        inNumPackets = inBuffer->mAudioDataByteSize / pRecordState->mDataFormat.mBytesPerPacket;
    }
    
    if (!pRecordState->mIsRunning) {
        return;
    }
    
    long sampleStart = (long)pRecordState->mCurrentPacket;
    long sampleEnd = (long)pRecordState->mCurrentPacket + inBuffer->mAudioDataByteSize / pRecordState->mDataFormat.mBytesPerPacket - 1;
    
    // %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    short * samples = (short *)inBuffer->mAudioData;
    long nsamples = sampleEnd - sampleStart + 1;

    printf("buffer received : %1.6ld from %1.6ld (#%07ld) to %1.6ld (#%07ld)\n", (sampleEnd - sampleStart + 1)/SAMPLE_RATE, sampleStart/SAMPLE_RATE, sampleStart, sampleEnd/SAMPLE_RATE, sampleEnd);

    for (int i = 0; i < 100; i ++) {
        printf("sample data:%i\n", samples[i]);
    }
    [(SinRecorder *)pRecordState->mSelf process:samples length:nsamples];
    
    // %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    pRecordState->mCurrentPacket += inNumPackets;
    
    AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
    
    if (pRecordState->mIsRunning) {
        [(SinRecorder *)pRecordState->mSelf stop];
    }
}

@interface SinRecorder()
{
    int mStep;
    int mState;
    int regValue;
    int regIndex;
    int regCount;
    int preRegCircle;
    int startingDetCount;
    int sampleingPointCount;
    
    BOOL isRegStart;
    BOOL isBeginning;
    BOOL startingDet;
    BOOL isStartCounting;
}
@end

@implementation SinRecorder
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initDatas];
    }
    return self;
}

- (void)dealloc
{
    AudioQueueDispose(_recordState.mQueue, true);

    [super dealloc];
}

- (void)initDatas
{
    mStep = STEP1;
    isBeginning = NO;
    startingDet = NO;
    preRegCircle = -1;
    startingDetCount = 0;
    isStartCounting = NO;
    mState = STATE_START;
    sampleingPointCount = 0;
}

- (void)start
{
    if (!_recordState.mIsRunning) {
        [self _setupAudioFormat];
        [self _deriveBufferSize:1000];
        _recordState.mCurrentPacket = 0;
        _recordState.mSelf = self;
        
        OSStatus status = noErr;
        status = AudioQueueNewInput(&_recordState.mDataFormat,
                                    HandleInputBuffer,
                                    &_recordState,
                                    CFRunLoopGetCurrent(),
                                    kCFRunLoopCommonModes,
                                    0,
                                    &_recordState.mQueue);
        
        ADAssert(noErr == status, @"Could not create queue.");
        
        for (int i = 0; i < kNumberBuffers; i++) {
            AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
            ADAssert(noErr == status, @"Could not allocate buffers.");
            AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
        }
        
        _recordState.mIsRunning = YES;
        status = AudioQueueStart(_recordState.mQueue, NULL);
        
        ADAssert(noErr == status, @"Could not start recording.");
    }
}

- (void)stop
{
    if (_recordState.mIsRunning) {
        AudioQueueStop(_recordState.mQueue, true);
        _recordState.mIsRunning = false;
    }
}

- (void)refreshRecord:(NSString *)text state:(NSString *)state
{
    if (_delegate && [_delegate respondsToSelector:@selector(updateRecord:state:)]) {
        [_delegate updateRecord:text state:state];
    }
}

- (void)_setupAudioFormat
{
    _recordState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
    _recordState.mDataFormat.mSampleRate = 44100.f;
    // 对于 linear PCM audio :mBitsPerChannel = 8 * sizeof (AudioSampleType)
    _recordState.mDataFormat.mBitsPerChannel = 8 * sizeof (AudioSampleType);
    _recordState.mDataFormat.mChannelsPerFrame = 1;
    // 对于未压缩音频mFramePerPacket值为1
    _recordState.mDataFormat.mFramesPerPacket = 1;
    // mBytesPerPacket 当 mFramesPerPacket 不确定时设为0
    // mBytesPerFrame = (number of channels) * sizeof (AudioSampleType);
    _recordState.mDataFormat.mBytesPerFrame = _recordState.mDataFormat.mBytesPerPacket = _recordState.mDataFormat.mChannelsPerFrame * sizeof(AudioSampleType);
    _recordState.mDataFormat.mReserved = 0;
    _recordState.mDataFormat.mFormatFlags = kAudioFormatFlagsCanonical;
}

// 根据时间设定buffer缓冲区的大小
- (void)_deriveBufferSize:(Float64)msec
{
    static const int maxBufferSize = 0x50000;
    
    int maxPacketSize = _recordState.mDataFormat.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(_recordState.mQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    
    Float64 numBytesPerSecond = round(_recordState.mDataFormat.mSampleRate * maxPacketSize * msec / 1000);
    _recordState.bufferByteSize = (UInt32) MIN(numBytesPerSecond, maxBufferSize);
}

- (void)process:(short *)samples length:(long)length
{
    short sh = 0;
    for (int i = 0; i < length; i ++) {
        short sh1 = (short)samples[i];
        sh1 &= 0xff;
        short sh2 = (short)samples[++i];
        sh2 <<= 8;
        sh = (short) (sh1 | sh2);
        
        if (!isStartCounting) {
            if (STEP1 == mStep) {
                if (sh < 0) {
                    mStep = STEP2;
                }
            }else if (STEP2 == mStep){
                if (sh > 0) {
                    isStartCounting = YES;
                    sampleingPointCount = 0;
                    mStep = STEP1;
                }
            }
        } else {
            ++ sampleingPointCount;
            if (STEP1 == mStep) {
                if (sh < 0) {
                    mStep = STEP2;
                }
            }else if (STEP2 == mStep){
                if (sh > 0) {
                    int pointCount = [self preReg:sampleingPointCount];
                    [self reg:pointCount];
                    sampleingPointCount = 0;
                    mStep = STEP1;
                }
            }
        }
    }
}

- (int)preReg:(int) samplingPointCount
{
    switch (samplingPointCount) {
        case 8:
        case 9:
        case 10:
        case 11:
        case 12:
            samplingPointCount = 10;
            break;
            
        case 13:
        case 14:
        case 15:
        case 16:
        case 17:
            samplingPointCount = 15;
            break;
            
        case 18:
        case 19:
        case 20:
            samplingPointCount = 19;
            break;
            
        case 21:
        case 22:
        case 23:
            samplingPointCount = 22;
            break;
            
        case 24:
        case 25:
        case 26:
            samplingPointCount = 25;
            break;
            
        case 27:
        case 28:
        case 29:
            samplingPointCount = 28;
            break;
            
        case 30:
        case 31:
        case 32:
            samplingPointCount = 31;
            break;
            
        default:
            samplingPointCount = 0;
            break;
    }
    
    return samplingPointCount;
}

- (void)reg:(int)pointCount
{
    if (!isBeginning) {
        if (!startingDet) {
            if (MAX_SAMPLING_POINT_COUNT == pointCount) {
                startingDet = YES;
                startingDetCount = 0;
            }
        } else {
            if (MAX_SAMPLING_POINT_COUNT == pointCount) {
                ++startingDetCount;
                
                if (startingDetCount >= MIN_REG_CIRCLE_COUNT) {
                    isBeginning = YES;
                    isRegStart = NO;
                    regCount = 0;
                }
            } else {
                startingDet = NO;
            }
        }
    } else {
        if (!isRegStart) {
            if (pointCount > 0) {
                regValue = pointCount;
                regIndex = INDEX(pointCount);
                isRegStart = YES;
                regCount = 1;
            }
        } else {
            if (pointCount == regValue) {
                ++regCount;
                
                if (regCount >= MIN_REG_CIRCLE_COUNT) {
                    // ok
                    if (regValue != preRegCircle) {
                        if (regIndex == 0) {
                            [self refreshRecord:@"recording..." state:nil];
                        }else if (regIndex == 6){
                            [self refreshRecord:@"end" state:nil];
                        }else{
                            [self refreshRecord:@"recording..." state:[NSString stringWithFormat:@"%i", INDEX(regIndex)]];
                        }
                        preRegCircle = regValue;
                    }
                    
                    isRegStart = NO;
                }
            } else {
                isRegStart = NO;
            }
        }
    }
}

@end
