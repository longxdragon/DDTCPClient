//
//  DDAsyncSocket.h
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/25.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DDAsyncSocket;

@protocol DDAsyncSocketDelegate <NSObject>
@optional
- (void)socket:(DDAsyncSocket *)socket didReadData:(NSData *)data;
- (void)socket:(DDAsyncSocket *)socket didConnect:(NSString *)host port:(uint16_t)port;
- (void)socketDidDisconnect:(DDAsyncSocket *)socket;
@end


@interface DDAsyncSocket : NSObject

@property (nonatomic, weak) id<DDAsyncSocketDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *socketHost;
@property (nonatomic, assign, readonly) uint16_t socketPort;
@property (nonatomic, assign) BOOL isDebug;

- (void)connectHost:(NSString *)host port:(uint16_t)port;
- (void)reconnect;
- (void)disConnect;
- (void)sendData:(NSData *)data;
- (BOOL)isConnected;
- (BOOL)isDisconnected;

@end
