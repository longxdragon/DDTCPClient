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

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _host = @"localhost";
    _port = 8080;
    
    
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
