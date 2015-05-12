//
//  ViewController.m
//  SinVoice
//
//  Created by ronglei on 14-9-26.
//  Copyright (c) 2014年 ronglei. All rights reserved.
//

#import "ViewController.h"
#import "SinPlayer.h"
#import "SinRecorder.h"

@interface ViewController ()<SinRecorderDelegate>

@property (strong, nonatomic) SinPlayer *player;
@property (strong, nonatomic) SinRecorder *recorder;

@property (weak, nonatomic) IBOutlet UITextField *sendTextField;
@property (weak, nonatomic) IBOutlet UILabel *stateLabel;
@property (weak, nonatomic) IBOutlet UILabel *recordLabel;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initDatas];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)initDatas
{
    _player = [[SinPlayer alloc] init];
    _recorder = [[SinRecorder alloc] init];
    _recorder.delegate = self;
}

#pragma mark - button method
- (IBAction)onPlayStartBtn:(id)sender
{
    if (_sendTextField.text != nil && _sendTextField.text.length > 0) {
        [_player play:_sendTextField.text]; 
    }else{
        NSLog(@"please input send code\n");
    }
}

- (IBAction)onPlayStopBtn:(id)sender
{
    [_player stop];
}

- (IBAction)onRecordStartBtn:(id)sender
{
    [_recorder start];
}

- (IBAction)onRecordStopBtn:(id)sender
{
    [_recorder stop];
}

#pragma mark - SinRencorderDelegate
- (void)updateRecord:(NSString *)text state:(NSString *)state
{
    [_recordLabel setText:text];
    [_stateLabel setText:state];
}
@end
