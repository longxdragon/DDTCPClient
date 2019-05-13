//
//  DDTCPClient.h
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/26.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DDTCPClient;

@protocol DDTCPClientDelegate <NSObject>
@optional
- (void)client:(DDTCPClient *)client didReadData:(NSData *)data;
- (void)client:(DDTCPClient *)client didConnect:(NSString *)host port:(uint16_t)port;
- (void)clientDidDisconnect:(DDTCPClient *)client;
- (void)client:(DDTCPClient *)client didSendHeartData:(NSData *)data;
@end

/**
 *  1. Send heart.
 *  2. Reconnet
 */
@interface DDTCPClient : NSObject

@property (nonatomic, weak) id<DDTCPClientDelegate> delegate;
@property (nonatomic, strong) NSData *heartData;
@property (nonatomic, assign) NSTimeInterval heartTimeInterval;
@property (nonatomic, assign) NSTimeInterval reconnectTimeInterval;
@property (nonatomic, assign) NSInteger reconnectCount;
@property (nonatomic, assign) BOOL isDebug;

- (instancetype)initWithSocketQueue:(dispatch_queue_t)socketQueue delegateQueue:(dispatch_queue_t)delegateQueue;
- (void)connectHost:(NSString *)host port:(uint16_t)port;
- (void)disConnect;
- (void)sendData:(NSData *)data;
- (BOOL)isConnected;
- (BOOL)isDisconnected;

@end
