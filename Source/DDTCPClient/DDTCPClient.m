//
//  DDTCPClient.m
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/26.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import "DDTCPClient.h"
#import <netinet/in.h>
#import <CocoaAsyncSocket/GCDAsyncSocket.h>
#import <SystemConfiguration/SystemConfiguration.h>

typedef void (^DDNetworkReachabilityStatusBlock)(BOOL reachable);

static void DDNetworkReachilityCallBack(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    DDNetworkReachabilityStatusBlock block = ((__bridge DDNetworkReachabilityStatusBlock)info);
    if (block) {
        block(((flags & kSCNetworkReachabilityFlagsReachable) != 0));
    }
}

static const void *DDNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void DDNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface DDTCPClient () <GCDAsyncSocketDelegate>

@property (nonatomic, assign) SCNetworkReachabilityRef ref;


@property (nonatomic) GCDAsyncSocket *socket;
@property (nonatomic) dispatch_queue_t socketQueue;
@property (nonatomic) dispatch_queue_t receiveQueue;

// Edit in socket queue
@property (nonatomic, strong) NSData *heart;
@property (nonatomic, assign) NSInteger reconnectFlag;
@property (nonatomic, assign) BOOL needReconnect;
@property (nonatomic, assign) BOOL networkReachable;

@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) UInt16 port;

// Edit in receive queue
@property (nonatomic, strong) NSMutableData *buffer;

@end

static NSTimeInterval DDSocketTimeout = -1;
static NSInteger DDSocketTag = 0;

@implementation DDTCPClient {
    void *IsOnSocketQueueOrTargetQueueKey;
    dispatch_source_t _heartTimer;
    dispatch_source_t _reconnectTimer;
}

- (void)dealloc {
    SCNetworkReachabilitySetDispatchQueue(self.ref, NULL);
    CFRelease(self.ref);
}

- (instancetype)init {
    return [self initWithReceiveQueue:nil];
}

- (instancetype)initWithReceiveQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        self.socketQueue = dispatch_queue_create("com.dd.socket", DISPATCH_QUEUE_SERIAL);
        self.receiveQueue = queue ? queue : dispatch_get_main_queue();
        
        NSAssert(self.receiveQueue != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                 @"The given receiveQueue parameter must not be a concurrent queue.");
        NSAssert(self.receiveQueue != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                 @"The given receiveQueue parameter must not be a concurrent queue.");
        NSAssert(self.receiveQueue != dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 @"The given receiveQueue parameter must not be a concurrent queue.");
        
        self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.receiveQueue socketQueue:self.socketQueue];
        self.socket.IPv4Enabled = YES;
        self.socket.IPv6Enabled = YES;
        self.socket.IPv4PreferredOverIPv6 = NO;
        
        self.buffer = [NSMutableData data];
        self.buffer.length = 0;
        
        IsOnSocketQueueOrTargetQueueKey = &IsOnSocketQueueOrTargetQueueKey;
        void *nonNullUnusedPointer = (__bridge void *)self;
        dispatch_queue_set_specific(self.socketQueue, IsOnSocketQueueOrTargetQueueKey, nonNullUnusedPointer, NULL);
        
        self.heartTimeInterval = 10;
        self.reconnectTimeInterval = 10;
        self.reconnectCount = 10;
        self.reconnectFlag = 0;
        self.isDebug = NO;
        self.needReconnect = YES;
        
        // Network reachability
        struct sockaddr_in addr;
        bzero(&addr, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        self.ref = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&addr);
        SCNetworkReachabilityFlags flags;
        SCNetworkReachabilityGetFlags(self.ref, &flags);
        self.networkReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    }
    return self;
}

#pragma mark - Network Monitoring

- (void)_startMonitoring {
    [self _stopMonitoring];
    
    __weak __typeof(self)wself = self;
    void (^block)(BOOL reachable) = ^(BOOL reachable) {
        __strong __typeof(wself)sself = wself;
        if (reachable) {
            sself.networkReachable = YES;
            // Reconnect
            if ([sself isDisconnected] && [self _checkNeedReconnectTimer]) {
                [sself _connect];
                [sself _resetConnect];
                [sself _startReconnectTimer];
            }
        } else {
            sself.networkReachable = NO;
        }
    };
    SCNetworkReachabilityContext context = { 0, (__bridge void *)block, DDNetworkReachabilityRetainCallback, DDNetworkReachabilityReleaseCallback, NULL };
    SCNetworkReachabilitySetCallback(self.ref, DDNetworkReachilityCallBack, &context);
    SCNetworkReachabilitySetDispatchQueue(self.ref, self.socketQueue);
}

- (void)_stopMonitoring {
    SCNetworkReachabilitySetDispatchQueue(self.ref, NULL);
}

#pragma mark - Send Heart

- (void)_sendHeart {
    BOOL success = [self sendData:self.heart];
    if (success) {
        if (self.isDebug) {
            NSLog(@"%@ -- <%p> host: %@ port: %d send heart", NSStringFromClass([self class]), self, self.host, self.port);
        }
        // Send heart
        NSData *copyData = [self.heart copy];
        dispatch_async(self.receiveQueue, ^{
            if (self.delegate && [self.delegate respondsToSelector:@selector(client:didSendHeartData:)]) {
                [self.delegate client:self didSendHeartData:copyData];
            }
        });
    }
}

- (void)_startHeartTimer {
    [self _stopHeartTimer];
    
    if (self.heartTimeInterval > 0) {
        // Thread start timer needs to be specified
        // No matter which thread the current method is executed in, the call of timer will call back in the specified thread
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.socketQueue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, self.heartTimeInterval * NSEC_PER_SEC), self.heartTimeInterval * NSEC_PER_SEC, self.heartTimeInterval * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            [self _sendHeart];
        });
        dispatch_resume(timer);
        _heartTimer = timer;
    }
}

- (void)_stopHeartTimer {
    if (_heartTimer) {
        dispatch_source_cancel(_heartTimer);
        _heartTimer = nil;
    }
}

#pragma mark - Reconnect Actions

- (void)_resetConnect {
    _reconnectFlag = 0;
}

- (void)_resetConnectState:(BOOL)state {
    _needReconnect = state;
}

- (BOOL)_checkNeedReconnectTimer {
    return (_needReconnect && _reconnectTimer == nil);
}

- (void)_reconnect {
    if (!self.networkReachable) {
        return;
    }
    if (self.reconnectCount >= 0 && _reconnectFlag >= self.reconnectCount) {
        return;
    }
    _reconnectFlag ++;
    
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d reconnect count %ld", NSStringFromClass([self class]), self.socket, self.host, self.port, (long)_reconnectFlag);
    }
    
    [self _connect];
}

- (void)_startReconnectTimer {
    [self _stopReconnectTimer];
    
    if (self.reconnectTimeInterval > 0) {
        // Thread start timer needs to be specified
        // No matter which thread the current method is executed in, the call of timer will call back in the specified thread
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.socketQueue);
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, self.reconnectTimeInterval * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(timer, ^{
            [self _reconnect];
        });
        dispatch_resume(timer);
        _reconnectTimer = timer;
    }
}

- (void)_stopReconnectTimer {
    if (_reconnectTimer) {
        dispatch_source_cancel(_reconnectTimer);
        _reconnectTimer = nil;
    }
}

#pragma mark - Socket Connect & Disconnect

- (void)_connect {
    // Cannot connect when the socket is not connected (connecting or connected)
    // Just connect when the socket is disconnected
    // Cancel the after connect actions
    if (![self isDisconnected]) {
        if (self.isDebug) {
            NSLog(@"%@ -- <%p> host: %@ port: %d connect error: already connecting or connected", NSStringFromClass([self class]), self, self.host, self.port);
        }
        return;
    }
    
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d connecting", NSStringFromClass([self class]), self, self.host, self.port);
    }
    
    NSError *error;
    [self.socket connectToHost:self.host onPort:self.port error:&error];
    if (error) {
        if (self.isDebug) {
            NSLog(@"%@ -- <%p> host: %@ port: %d connect error: %@", NSStringFromClass([self class]), self, self.host, self.port, error);
        }
    }
}

- (void)_disConnect {
    [self.socket disconnect];
}

- (void)_didSendData:(NSData *)data {
    if (self.socket.isDisconnected) {
        [self _connect];
    }
    [self.socket writeData:data withTimeout:DDSocketTimeout tag:DDSocketTag];
}

// Handle on receiveQueue (Serial queue), so nolock.
- (void)_didReceiveData:(NSData *)data {
    [_buffer appendData:data];
    
    while (_buffer.length > 4) {
        // Format first four byte to int
        Byte *byte = (Byte *)_buffer.bytes;
        int length = (int)((byte[3] & 0xFF) | ((byte[2] & 0xFF)<<8) | ((byte[1] & 0xFF)<<16) | ((byte[0] & 0xFF)<<24));
        
        if (length == 0) {
            if (_buffer.length >= 4) {
                NSData *tmp = [_buffer subdataWithRange:NSMakeRange(4, _buffer.length - 4)];
                
                [_buffer setLength:0];
                [_buffer appendData:tmp];
            } else {
                [_buffer setLength:0];
            }
            [self _callback:nil];
            
        } else {
            NSUInteger packageLength = 4 + length;
            if (packageLength <= _buffer.length) {
                NSData *data = [_buffer subdataWithRange:NSMakeRange(4, length)];
                NSData *tmp = [_buffer subdataWithRange:NSMakeRange(packageLength, _buffer.length - packageLength)];
                
                [_buffer setLength:0];
                [_buffer appendData:tmp];
                [self _callback:data];
            } else {
                break;
            }
        }
    }
}

- (void)_didReadData {
    // Run in receiveQueue, change to socketQueue
    dispatch_async(self.socketQueue, ^{
        [self.socket readDataWithTimeout:DDSocketTimeout tag:DDSocketTag];
    });
}

- (void)_callback:(NSData *)data {
    if (self.delegate && [self.delegate respondsToSelector:@selector(client:didReadData:)]) {
        [self.delegate client:self didReadData:data];
    }
}

#pragma mark - Public

- (void)connectHost:(NSString *)host port:(uint16_t)port {
    void (^block)(void) = ^(void) {
        self.host = host;
        self.port = port;
        
        [self _resetConnectState:YES]; // Need reconnect
        [self _connect];
        [self _startMonitoring];  // start network monitoring when connect
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_async(self.socketQueue, block);
    }
}

- (void)disConnect {
    void (^block)(void) = ^(void) {
        [self _resetConnectState:NO];
        [self _stopReconnectTimer];
        [self _disConnect];
        [self _stopMonitoring];  // stop network monitoring when disconnect
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_async(self.socketQueue, block);
    }
}

- (void)setHeartData:(NSData *)heartData {
    NSData *copyData = [heartData copy];
    
    void (^block)(void) = ^(void) {
        if ([self.heart isEqualToData:copyData]) return;
        self.heart = copyData;
        
        if (copyData) {
            [self _sendHeart];
        }
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_async(self.socketQueue, block);
    }
}

// Append package length in first 4 byte
- (BOOL)sendData:(NSData *)data {
    if (!data || ![self isConnected]) {
        return NO;
    }
    
    NSUInteger length = data.length;
    NSData *copyData = [data copy]; // fix input mutable data
    
    void (^block)(void) = ^(void) {
        // Format data length <int to data>
        Byte byte[4];
        byte[0] = (Byte)((length>>24) & 0xFF);
        byte[1] = (Byte)((length>>16) & 0xFF);
        byte[2] = (Byte)((length>>8) & 0xFF);
        byte[3] = (Byte)(length & 0xFF);
        NSData *lengthData = [NSData dataWithBytes:byte length:4];
        
        NSMutableData *mutableData = [NSMutableData data];
        [mutableData appendData:lengthData];
        [mutableData appendData:copyData];
        
        [self _didSendData:[mutableData copy]];
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_async(self.socketQueue, block);
    }
    return YES;
}

- (BOOL)isConnected {
    return [self.socket isConnected]; // GCDAsyncSocket did the action in socket queue
}

- (BOOL)isDisconnected {
    return [self.socket isDisconnected];
}

- (NSString *)socketHost {
    __block NSString *host = nil;
    void (^block)(void) = ^(void) {
        host = [self.host copy];
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_sync(self.socketQueue, ^{
            block();
        });
    }
    return host;
}

- (uint16_t)socketPort {
    __block uint16_t port = 0;
    void (^block)(void) = ^(void) {
        port = self.port;
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_sync(self.socketQueue, ^{
            block();
        });
    }
    return port;
}

- (NSData *)heartData {
    __block NSData *copyData = nil;
    void (^block)(void) = ^(void) {
        copyData = self.heart;
    };
    if (dispatch_get_specific(IsOnSocketQueueOrTargetQueueKey)) {
        block();
    } else {
        dispatch_sync(self.socketQueue, block);
    }
    return copyData;
}

#pragma mark - GCDAsyncSocketDelegate
// All delegate methods run in receiveQueue

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d connect successed", NSStringFromClass([self class]), self, self.socketHost, self.socketPort);
    }
    // Reset default value
    self.buffer.length = 0;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(client:didConnect:port:)]) {
        [self.delegate client:self didConnect:host port:port];
    }
    
    dispatch_async(self.socketQueue, ^{
        [self _startHeartTimer];
        [self _stopReconnectTimer];
    });
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d disConnect error: %@", NSStringFromClass([self class]), self, self.socketHost, self.socketPort, err);
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(clientDidDisconnect:)]) {
        [self.delegate clientDidDisconnect:self];
    }
    
    dispatch_async(self.socketQueue, ^{
        [self _stopHeartTimer];
        
        if ([self _checkNeedReconnectTimer]) {
            [self _resetConnect];
            [self _startReconnectTimer];
        }
    });
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d did write", NSStringFromClass([self class]), self, self.socketHost, self.socketPort);
    }
    [self _didReadData];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (self.isDebug) {
        NSLog(@"%@ -- <%p> host: %@ port: %d did receive data", NSStringFromClass([self class]), self, self.socketHost, self.socketPort);
    }    
    [self _didReceiveData:data];
    [self _didReadData];
}

@end
