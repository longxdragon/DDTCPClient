//
//  ViewController.m
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/25.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import "ViewController.h"
#import "DDTCPClient.h"

#import <DDCryptor/DDCryptor.h>

@interface ViewController () <DDTCPClientDelegate>

@end

@implementation ViewController {
    DDTCPClient *_socket;
    NSInteger _count;
    NSString *_host;
    uint16_t _port;
}

NSString *JSONString(id obj) {
    if (![NSJSONSerialization isValidJSONObject:obj]) {
        return nil;
    }
    __autoreleasing NSError *error = nil;
    NSData *result = [NSJSONSerialization dataWithJSONObject:obj options:kNilOptions error:&error];
    if (error) {
        return nil;
    }
    return [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _host = @"192.168.1.132";//@"211.151.144.74";//
    _port = 9011;//1235;//
    
    
    DDTCPClient *socket = [[DDTCPClient alloc] init];
    socket.delegate = self;
    socket.isDebug = YES;
    socket.reconnectCount = 5;
    socket.reconnectTimeInterval = 5;
    _socket = socket;
    
    
    long long time = (long long)[[NSDate date] timeIntervalSince1970] * 1000;
    NSString *auth = [NSString stringWithFormat:@"%lld_KOUDAITCP", time];
    NSString *enAuth = [auth dd_3desEncryptWithKey:@"lPrzT8BMoJt2dUSslfwn3Vkl" iv:@"sojexcom"];
    
    NSDictionary *dic = @{ @"type" : @"subcribe", @"auth" : enAuth ?: @"", @"ids" : @[@"12", @"194", @"195"]};
    NSString *registStr = JSONString(dic);
    NSData *registData = [registStr dataUsingEncoding:NSUTF8StringEncoding];
    
    [socket sendData:registData];
    
    
    NSDictionary *heart = @{ @"type" : @"heartbeat" };
    NSString *heartStr = JSONString(heart);
    NSData *heartData = [heartStr dataUsingEncoding:NSUTF8StringEncoding];

    [socket setHeartData:heartData];
}

- (IBAction)connect {
    [_socket connectHost:_host port:_port];
}

- (IBAction)disConnect {
    [_socket disConnect];
}


- (void)client:(DDTCPClient *)client didReadData:(NSData *)data {
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"DDAsyncSocket -- %@", str);
}
- (void)client:(DDTCPClient *)client didConnect:(NSString *)host port:(uint16_t)port {
    
}
- (void)clientDidDisconnect:(DDTCPClient *)client {
    
}

@end
