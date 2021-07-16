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
/**
 * Callback of received message
 * Call on the specified thread, when you set the receive queue
 */
- (void)client:(DDTCPClient *)client didReadData:(NSData *)data;
/**
 * Callback of did connected
 * Call on the specified thread, when you set the receive queue
*/
- (void)client:(DDTCPClient *)client didConnect:(NSString *)host port:(uint16_t)port;
/**
 * Callback of disconnected
 * Call on the specified thread, when you set the receive queue
*/
- (void)clientDidDisconnect:(DDTCPClient *)client;
/**
 * Callback of send heart data
 * Call on the specified thread, when you set the receive queue
*/
- (void)client:(DDTCPClient *)client didSendHeartData:(NSData *)data;

@end

@interface DDTCPClient : NSObject

// The delegate of the callback informations
@property (nonatomic, weak) id<DDTCPClientDelegate> delegate;

// The time interval of sending heart data. Default is 10s
@property (nonatomic, assign) NSTimeInterval heartTimeInterval;

// How often do I reconnect?
// Only disconnect when the network is not good.
// If I disconnect manually, I will not reconnect
//
// The time interval of reconnect. Default is 10s
@property (nonatomic, assign) NSTimeInterval reconnectTimeInterval;

// The time interval of connenting. Default is 5s
@property (nonatomic, assign) NSTimeInterval connectTimeInterval;

// The count of reconnect. Default is 10
@property (nonatomic, assign) NSInteger reconnectCount;

// Print log or not
@property (nonatomic, assign) BOOL isDebug;

// Heartbeat packet data. Keep the tcp unbroken.
@property (nonatomic, strong) NSData *heartData;

// The host of socket, just readonly and thread safe
@property (nonatomic, copy, readonly) NSString *socketHost;

// The post of socket, just readonly and thread safe
@property (nonatomic, assign, readonly) uint16_t socketPort;

/**
 * Appoint the receive queue and initialization
 * If queue is nil, Default is dispatch_get_main_queue
 */
- (instancetype)initWithReceiveQueue:(dispatch_queue_t)queue;

/**
 * Connects to the given host and port.
 */
- (void)connectHost:(NSString *)host port:(uint16_t)port;

/**
 * Disconnects immediately (synchronously). Any pending reads or writes are dropped.
 */
- (void)disConnect;

/**
 * Send message data and return whether send success.
 * Return 'NO' when data is nil or current socket is not connected (connecting or disconnected)
 */
- (BOOL)sendData:(NSData *)data;

/**
 * Returns whether the socket is connected.
 */
- (BOOL)isConnected;

/**
 * Returns whether the socket is disconnected.
 */
- (BOOL)isDisconnected;

@end
