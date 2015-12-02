//
//  SinVoice.h
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#ifndef SinVoice_SinVoice_h
#define SinVoice_SinVoice_h

#define kNumberBuffers          3

#define SAMPLE_RATE             44100                   // simple rate 采样率
#define INTERVAL                1000                    // 1000ms 1s
#define BITS_16                 32768                   // 采样大小 16bit

#define SOUND_DURATION          200                     // 每个音符持续200ms
#define SILENT_DURATION         1000                    // 无声持续时间1000ms
#define SOUND_SAMPLE_COUNT      (SOUND_DURATION * SAMPLE_RATE) / INTERVAL   // sound采样点个数
#define SILENT_SAMPLE_COUNT     (SILENT_DURATION * SAMPLE_RATE) / INTERVAL  // silent采样点个数

#ifdef ADUseAsserts
#define ADAssert(format, ...) NSAssert(format, ## __VA_ARGS__)
#else
#define ADAssert(format, ...)
#endif

#endif
