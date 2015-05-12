//
//  SinPlayer.m
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#import "SinPlayer.h"

void HandleOutputBuffer(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer) {
    AQPlayState * pPlayState = (AQPlayState *)inUserData;
    
    if ( ! pPlayState->mIsRunning) {
        return;
    }
    
    // %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    // inBuffer表示已经播放完的audio queue buffer(已经开始播放后)
    // 等待往里面添加下面要播放的audio data后,重新放到buffer queue的队尾
    UInt32 numBytesToPlay = inBuffer->mAudioDataBytesCapacity;
    UInt32 numPackets = numBytesToPlay/pPlayState->mDataFormat.mBytesPerPacket;
    
	SInt8 * buffer = (SInt8 *)inBuffer->mAudioData;
    
    // 每个buffer中有添加 44100个采样点数据
	for(long i = (long)pPlayState->mCurrentPacket; i < pPlayState->mCurrentPacket + numPackets; i++) {
        long idx = i % pPlayState->mCodeLength;
        // 循环播放code
		buffer[i-pPlayState->mCurrentPacket] = pPlayState->mCode[idx];
	}
    
    // %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    inBuffer->mAudioDataByteSize = numPackets;
    AudioQueueEnqueueBuffer(pPlayState->mQueue, inBuffer, 0, NULL);
    pPlayState->mCurrentPacket += numPackets;
}

@interface SinPlayer()

@property (retain, nonatomic) NSArray *codeArray;
@property (retain, nonatomic) NSArray *codeFrequencyArray;

@end

@implementation SinPlayer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _playState.mIsRunning = NO;
        _codeArray = [[NSArray alloc] initWithArray:@[@"1422",@"1575",@"1764",@"2004",@"2321",@"2940",@"4410"]];
        _codeFrequencyArray = [[NSArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    AudioQueueDispose(_playState.mQueue, true);
    if (_playState.mCode == NULL) {
        free(_playState.mCode);
    }
    [super dealloc];
}

- (void)_setupAudioFormat
{
    _playState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
    _playState.mDataFormat.mSampleRate = 44100.f;
    // 对于 linear PCM audio :mBitsPerChannel = 8 * sizeof (AudioSampleType)
    _playState.mDataFormat.mBitsPerChannel = 8 * sizeof (AudioSampleType);
    _playState.mDataFormat.mChannelsPerFrame = 1;
    // 对于未压缩音频mFramePerPacket值为1
    _playState.mDataFormat.mFramesPerPacket = 1;
    // mBytesPerPacket 当 mFramesPerPacket 不确定时设为0
    // mBytesPerFrame = (number of channels) * sizeof (AudioSampleType);
    _playState.mDataFormat.mBytesPerFrame = _playState.mDataFormat.mBytesPerPacket = _playState.mDataFormat.mChannelsPerFrame * sizeof(AudioSampleType);
    _playState.mDataFormat.mReserved = 0;
    _playState.mDataFormat.mFormatFlags = kAudioFormatFlagsCanonical;
}

// 根据时间设定buffer缓冲区的大小
- (void)_deriveBufferSize:(Float64)msec
{
    static const int maxBufferSize = 0x50000;
    
    int maxPacketSize = _playState.mDataFormat.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(_playState.mQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    
    Float64 numBytesPerSecond = round(_playState.mDataFormat.mSampleRate * maxPacketSize * msec / 1000);
    _playState.bufferByteSize = (UInt32) MIN(numBytesPerSecond, maxBufferSize);
}

- (void)stop
{
    AudioQueueStop(_playState.mQueue, true);
    _playState.mIsRunning = NO;
    free(_playState.mCode);
}
    

- (void)play:(NSString *)msg
{
    [self _setupAudioFormat];
    _playState.mCurrentPacket = 0;
    _playState.mCodeLength = 0;
    [self encodeMessage:msg];
    [self _deriveBufferSize:1000];
    
    OSStatus status = noErr;
    //Creates a new audio queue for playing audio data
    // 播放开始后才会开始调用callback function :HandleOutputBuffer
    status = AudioQueueNewOutput(&_playState.mDataFormat,
                                 HandleOutputBuffer,
                                 &_playState,
                                 CFRunLoopGetCurrent(),
                                 kCFRunLoopCommonModes,
                                 0,
                                 &_playState.mQueue);
    
    ADAssert(noErr == status, @"Could not create queue.");
    
    _playState.mIsRunning = YES;
    //向buffer aqueue中添加三个audio queue buffer准备开始播放
    for (int i = 0; i < kNumberBuffers; i++) {
        // 为mBuffers[i]申请bufferByteSize大小的内存
        status = AudioQueueAllocateBuffer(_playState.mQueue, _playState.bufferByteSize, &_playState.mBuffers[i]);
        ADAssert(noErr == status, @"Could not allocate buffers.");
        HandleOutputBuffer(&_playState, _playState.mQueue, _playState.mBuffers[i]);
    }
    
    status = AudioQueueStart(_playState.mQueue, NULL);
    ADAssert(noErr == status, @"Could not start playing.");
}

- (void)encodeMessage:(NSString *)message
{
    _codeFrequencyArray = [self transToFrequency:message];
    int totalSize = SOUND_SAMPLE_COUNT * 2 + SILENT_SAMPLE_COUNT * 2;
    _playState.mCode = (char *)calloc(totalSize, sizeof(char));
    
    for (NSString *frequency in _codeFrequencyArray) {
        [self gen:[frequency intValue] dur:SOUND_DURATION];
    }
    
    [self gen:0 dur:SILENT_DURATION];
}

- (NSArray *)transToFrequency:(NSString *)code
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (int i = 0; i < code.length; i ++) {
        [array addObject:[_codeArray objectAtIndex:[[code substringWithRange:NSMakeRange(i, 1)] integerValue]]];
    }
    return array;
}

- (void)gen:(int)genRate dur:(int)dur
{
    int buffSize = 0;
    int n = BITS_16/2;
    // totalCount 100ms需要采样的个数
    int totalCount = SOUND_SAMPLE_COUNT;
    // per 每个采样点之间角度间隔
    double per = (genRate/(double)SAMPLE_RATE)*2*M_PI;
    double d = 0;
    
    for (int i = 0; i < totalCount; i++) {
        int outPrint = (int)(sin(d)*n)+128;
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)(outPrint & 0xff);
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)((outPrint >> 8) & 0xff);
        
        d+=per;
    }
    _playState.mCodeLength += totalCount * 2;
}

@end
