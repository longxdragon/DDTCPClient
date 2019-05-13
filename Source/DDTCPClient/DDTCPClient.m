//
//  DDTCPClient.m
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/26.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import "DDTCPClient.h"
#import "DDAsyncSocket.h"
#import "AFNetworkReachabilityManager.h"

@interface DDTCPClient () <DDAsyncSocketDelegate>

@property (nonatomic, strong) DDAsyncSocket *socket;
@property (nonatomic) dispatch_queue_t socketQueue;
@property (nonatomic) dispatch_queue_t receiveQueue;
@property (nonatomic) dispatch_queue_t defaultSocketQueue;
@property (nonatomic) dispatch_queue_t defaultReceiveQueue;
@property (nonatomic, assign) NSInteger reconnectFlag;
@property (nonatomic, assign) BOOL needReconnect;
@property (nonatomic, strong) AFNetworkReachabilityManager *reach;
@property (nonatomic, assign) BOOL networkReachable;

@end

@implementation DDTCPClient

- (instancetype)init {
    return [self initWithSocketQueue:nil delegateQueue:nil];
}

- (instancetype)initWithSocketQueue:(dispatch_queue_t)socketQueue delegateQueue:(dispatch_queue_t)delegateQueue {
    if (self = [super init]) {
        // The socket queue can't be concurrent queue
        if (socketQueue == dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0) ||
            socketQueue == dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) ||
            socketQueue == dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            socketQueue = nil;
        }
        
        self.defaultSocketQueue = dispatch_queue_create("com.dd.socket", DISPATCH_QUEUE_SERIAL);
        self.defaultReceiveQueue = dispatch_queue_create("com.dd.receive", DISPATCH_QUEUE_SERIAL);
        self.socketQueue = socketQueue;
        self.receiveQueue = delegateQueue;
        
        self.socket = [[DDAsyncSocket alloc] initWithSocketQueue:self.socketQueue ?: self.defaultSocketQueue delegateQueue:self.receiveQueue ?: self.defaultReceiveQueue];
        self.socket.delegate = self;
        
        self.heartTimeInterval = 10;
        self.reconnectTimeInterval = 10;
        self.reconnectCount = 10;
        self.reconnectFlag = 0;
        self.isDebug = NO;
        self.networkReachable = YES;
        self.needReconnect = YES;
    }
    return self;
}

#pragma mark - Public

- (void)setIsDebug:(BOOL)isDebug {
    _isDebug = isDebug;
    self.socket.isDebug = isDebug;
}

- (void)setHeartData:(NSData *)heartData {
    NSAssert([NSThread isMainThread], @"Must operation at main thread");
    
    if ([_heartData isEqualToData:heartData]) {
        return;
    }
    _heartData = heartData;
    
    // Send heart
    [self _sendHeart];
}

- (void)connectHost:(NSString *)host port:(uint16_t)port {
    NSAssert([NSThread isMainThread], @"Must operation at main thread");
    
    [self.socket connectHost:host port:port];
    
    // Add network monitoring
    [self _startMonitoring];
}

- (void)disConnect {
    NSAssert([NSThread isMainThread], @"Must operation at main thread");
    
    // Custom disconnect, so do not need reconnect
    _needReconnect = NO;
    
    [self.socket disConnect];
    
    // Remove network monitoring
    [self _stopMonitoring];
}

- (void)sendData:(NSData *)data {
    NSAssert([NSThread isMainThread], @"Must operation at main thread");
    
    [self _sendData:data];
}

- (BOOL)isConnected {
    return [self.socket isConnected];
}

- (BOOL)isDisconnected {
    return [self.socket isDisconnected];
}

#pragma mark - DDAsyncSocketDelegate

- (void)socket:(DDAsyncSocket *)socket didReadData:(NSData *)data {
    void (^callback)(void) = ^(void) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(client:didReadData:)]) {
            [self.delegate client:self didReadData:data];
        }
        [self _delaySendHeart];
    };
    dispatch_async(self.receiveQueue ?: dispatch_get_main_queue(), callback);
}

- (void)socket:(DDAsyncSocket *)socket didConnect:(NSString *)host port:(uint16_t)port {
    void (^callback)(void) = ^(void) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(client:didConnect:port:)]) {
            [self.delegate client:self didConnect:host port:port];
        }
        [self _delaySendHeart];
        
        [self _resetConnect];
    };
    dispatch_async(self.receiveQueue ?: dispatch_get_main_queue(), callback);
}

- (void)socketDidDisconnect:(DDAsyncSocket *)socket {
    void (^callback)(void) = ^(void) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(clientDidDisconnect:)]) {
            [self.delegate clientDidDisconnect:self];
        }
        [self _cancelSendHeart];
        
        if (self.needReconnect) {
            // Reconnect delay
            [self _delayReconnect];
        }
    };
    dispatch_async(self.receiveQueue ?: dispatch_get_main_queue(), callback);
}

#pragma mark - Private

// Cannot send data when the socket is not connected
- (BOOL)_sendData:(NSData *)data {
    if (!data || ![self isConnected]) {
        return NO;
    }
    [self.socket sendData:data];
    return YES;
}

- (void)_startMonitoring {
    [self _stopMonitoring];
    
    self.reach = [AFNetworkReachabilityManager managerForDomain:self.socket.socketHost];
    self.networkReachable = self.reach.isReachable;
    
    __weak typeof(self) wself = self;
    [self.reach setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        __strong typeof(self) sself = wself;
        if (!sself) {
            return;
        }
        if (status == AFNetworkReachabilityStatusReachableViaWWAN || status == AFNetworkReachabilityStatusReachableViaWiFi) {
            sself.networkReachable = YES;
            // Reconnect
            [sself _cancelReconnect];
            [sself _reconnect];
        }else {
            sself.networkReachable = NO;
        }
    }];
    
    [self.reach startMonitoring];
}

- (void)_stopMonitoring {
    [self.reach stopMonitoring];
    [self setReach:nil];
}

#pragma mark - Send Heart

- (void)_sendHeart {
    BOOL success = [self _sendData:_heartData];
    if (success) {
        if (self.isDebug) {
            NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d send heart", self.socket, self.socket.socketHost, self.socket.socketPort);
        }
        // Send heart
        void (^callback)(void) = ^(void) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(client:didSendHeartData:)]) {
                [self.delegate client:self didSendHeartData:self->_heartData];
            }
        };
        dispatch_async(self.receiveQueue ?: dispatch_get_main_queue(), callback);
        
        [self _delaySendHeart];
    }
}

- (void)_delaySendHeart {
    [self _cancelSendHeart];
    [self performSelector:@selector(_sendHeart) withObject:nil afterDelay:self.heartTimeInterval];
}

- (void)_cancelSendHeart {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendHeart) object:nil];
}

#pragma mark - Reconnect

- (void)_resetConnect {
    _reconnectFlag = 0;
    _needReconnect = YES;
    
    [self _cancelReconnect];
}

- (void)_reconnect {
    if (!self.networkReachable) {
        return;
    }
    // Cannot connect when connecting or connected
    if (![self.socket isDisconnected]) {
        return;
    }
    if (self.reconnectCount >= 0 && _reconnectFlag >= self.reconnectCount) {
        return;
    }
    _reconnectFlag ++;
    
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d reconnect count %ld", self.socket, self.socket.socketHost, self.socket.socketPort, (long)_reconnectFlag);
    }
    [self.socket reconnect];
}

- (void)_delayReconnect {
    [self _cancelReconnect];
    [self performSelector:@selector(_reconnect) withObject:nil afterDelay:self.reconnectTimeInterval];
}

- (void)_cancelReconnect {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reconnect) object:nil];
}

@end
