//
//  ViewController.m
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/25.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import "ViewController.h"
#import "DDTCPClient.h"


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
    
    _host = @"192.168.1.132";
    _port = 9011;
    
    
    DDTCPClient *socket = [[DDTCPClient alloc] init];
    socket.delegate = self;
    socket.isDebug = YES;
    socket.reconnectCount = 5;
    socket.reconnectTimeInterval = 5;
    _socket = socket;
    
    
    NSString *registStr = @"I'm register informations";
    NSData *registData = [registStr dataUsingEncoding:NSUTF8StringEncoding];
    
    [socket sendData:registData];
    
    
    NSString *heartStr = @"I'm heart informations";
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
