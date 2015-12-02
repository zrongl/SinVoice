//
//  SinPlayer.m
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#import "SinPlayer.h"

/**
 *  AudioQueueOutputCallback
 *
 *  @param inUserData  AudioQueueNewOutput()函数中自定义的结构体指针inUserData
 *  @param inAQ        指向audio queue对象的指针
 *  @param inBuffer    等待填充数据并放置进buffer queue的buffer
 */
void HandleOutputBuffer(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer) {
    AQPlayState * pPlayState = (AQPlayState *)inUserData;
    
    if ( ! pPlayState->mIsRunning) {
        return;
    }
    
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
        // 0~7不同数字对应不同的声音频率
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
    
    // 码率
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
    /*!
     @function   AudioQueueNewOutput
     @abstract   创建一个新的audio queue用于播放音频数据，
     调用了AudioQueueStart()才会开始播放
     当第一个buffer中的数据播放完之后，才会调用callback
     
     @param      inFormat
     指向描述将被播放的音频数据格式的结构体指针，对于线性PCM来说，只有隔行扫描的格式能够被支持。
     @param      inCallbackProc
     指向一个回调函数，当audio queue播放玩一个buffer后会将该buffer传给这个回调函数
     @param      inUserData
     自定义结构体的指针，会传递给回调函数
     @param      inCallbackRunLoop
     回调函数将被在执行在inCallbackRunLoop指定的事件循环中
     如果值为NULL，回调函数将被安排在audio queue的内部线程中执行
     @param      inCallbackRunLoopMode
     指定RunLoopMode，默认为kCFRunLoopCommonModes
     @param      inFlags
     保留，传0
     @param      outAQ
     返回的时候，该变量会指向新创建的audio queue对象
     
     @result     An OSStatus result code.
     */
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
//    _codeFrequencyArray = [self genFrequencys];
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

- (NSArray *)genFrequencys
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    int low = 100;
    int high = 2000;
    int copies = 20;
    int space = (high - low)/copies;
    for (int i = 1; i < copies; i ++) {
        [array addObject:[NSString stringWithFormat:@"%d", 20+i*space]];
    }
    return array;
}

/**
 *  根据频率和持续时间生成采样点数据
 *
 *  @param genRate  生成的声波的频率
 *  @param dur      声波播放时长
 *
 */
- (void)gen:(int)genRate dur:(int)dur
{
    int buffSize = 0;
    // 振幅
    int n = BITS_16/2;
    // totalCount 持续时间为200ms的声音的采样点个数
    int totalCount = (dur*SAMPLE_RATE)/INTERVAL;
    // 1/SAMPLE_RATE 表示采样时间间隔
    // (genRate/(double)SAMPLE_RATE)*2*M_PI 表示每个时间间隔内(对于频率为genRate的波)角度变化的大小
    // per 每个采样点之间角度间隔
    double per = (genRate/(double)SAMPLE_RATE)*2*M_PI;
    double d = 0;
    
    for (int i = 0; i < totalCount; i++) {
        // 采样精度是16bit，因此每个采样点数据位数为16位，而mCode类型是char*占8bit大小
        // 利用mCode存储采样数据时需要将第一个采样点数据的低8位和高8位分别存储到mCode[0]和mCode[1]的位置，以此类推
#if 0
        int outPrint = (int)(sin(d)*n)+128;
        // outPrint&0xff == outPrint%256
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)(outPrint & 0xff);
        // (outPrint>>8)&0xff == (outPrint/256)%256
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)((outPrint >> 8) & 0xff);
#else
        int outPrint = (int)(sin(d)*n);
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)outPrint;
        _playState.mCode[_playState.mCodeLength + buffSize++] = (SignedByte)(outPrint >> 8);
#endif
        d+=per;
    }
    _playState.mCodeLength += totalCount*2;
}

@end
