//
//  DDAsyncSocket.m
//  DDTCPClient
//
//  Created by longxdragon on 2018/2/25.
//  Copyright © 2018年 longxdragon. All rights reserved.
//

#import "DDAsyncSocket.h"
#import <CocoaAsyncSocket/GCDAsyncSocket.h>

@interface DDAsyncSocket () <GCDAsyncSocketDelegate>

@property (nonatomic) GCDAsyncSocket *socket;
@property (nonatomic) dispatch_queue_t socketQueue;
@property (nonatomic) dispatch_queue_t receiveQueue;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) UInt16 port;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) BOOL isReading;

@end

@implementation DDAsyncSocket

static NSTimeInterval DDSocketTimeout = -1;
static NSInteger DDSocketTag = 0;

- (instancetype)initWithSocketQueue:(dispatch_queue_t)socketQueue delegateQueue:(dispatch_queue_t)delegateQueue {
    if (self = [super init]) {
        self.socketQueue = socketQueue;
        self.receiveQueue = delegateQueue;
        
        self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.receiveQueue socketQueue:self.socketQueue];
        self.socket.IPv4Enabled = YES;
        self.socket.IPv6Enabled = YES;
        self.socket.IPv4PreferredOverIPv6 = NO;
        
        self.buffer = [NSMutableData data];
        self.buffer.length = 0;
        self.isReading = NO;
    }
    return self;
}

- (void)_connect {
    // Cannot connect when the socket is not connected (connecting or connected)
    // Just connect when the socket is disconnected
    // Cancel the after connect actions
    if (![self isDisconnected]) {
        if (self.isDebug) {
            NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d connect error: already connecting or connected", self, self.host, self.port);
        }
        return;
    }
    
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d connecting", self, self.host, self.port);
    }
    
    NSError *error;
    [self.socket connectToHost:self.host onPort:self.port error:&error];
    if (error) {
        if (self.isDebug) {
            NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d connect error: %@", self, self.host, self.port, error);
        }
    }
}

- (void)_disConnect {
    [self.socket disconnect];
}

// Handle on socketQueue (Serial queue), so nolock.
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

// Run in socketQueue
- (void)_didReadData {
    if (self.isReading) {
        return;
    }
    self.isReading = YES;
    
    [self.socket readDataWithTimeout:DDSocketTimeout tag:DDSocketTag];
}

- (void)_didSendData:(NSData *)data {
    dispatch_async(self.socketQueue, ^{
        if (self.socket.isDisconnected) {
            [self _connect];
        }
        [self.socket writeData:data withTimeout:DDSocketTimeout tag:DDSocketTag];
    });
}

- (void)_callback:(NSData *)data {
    dispatch_async(self.receiveQueue, ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didReadData:)]) {
            [self.delegate socket:self didReadData:data];
        }
    });
}

#pragma mark - Public

- (void)connectHost:(NSString *)host port:(uint16_t)port {
    dispatch_async(self.socketQueue, ^{
        self.host = host;
        self.port = port;
        
        [self _connect];
    });
}

- (void)reconnect {
    [self connectHost:self.host port:self.port];
}

- (void)disConnect {
    dispatch_async(self.socketQueue, ^{
        [self _disConnect];
    });
}

// Append package length in first 4 byte
- (void)sendData:(NSData *)data {
    if (!data || ![self isConnected]) {
        return;
    }
    
    NSUInteger length = data.length;
    
    // Format data length <int to data>
    Byte byte[4];
    byte[0] = (Byte)((length>>24) & 0xFF);
    byte[1] = (Byte)((length>>16) & 0xFF);
    byte[2] = (Byte)((length>>8) & 0xFF);
    byte[3] = (Byte)(length & 0xFF);
    NSData *lengthData = [NSData dataWithBytes:byte length:4];
    
    NSMutableData *mutableData = [NSMutableData data];
    [mutableData appendData:lengthData];
    [mutableData appendData:data];
    
    [self _didSendData:[mutableData copy]];
}

- (BOOL)isConnected {
    return [self.socket isConnected];
}

- (BOOL)isDisconnected {
    return [self.socket isDisconnected];
}

- (NSString *)socketHost {
    return self.host;
}

- (uint16_t)socketPort {
    return self.port;
}

#pragma mark - GCDAsyncSocketDelegate
// All delegate methods run in receiveQueue

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d connect successed", self, self.host, self.port);
    }
    // Reset default value
    dispatch_async(self.socketQueue, ^{
        self.buffer.length = 0;
        self.isReading = NO;
    });
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didConnect:port:)]) {
        [self.delegate socket:self didConnect:host port:port];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d disConnect error: %@", self, self.host, self.port, err);
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketDidDisconnect:)]) {
        [self.delegate socketDidDisconnect:self];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d did write", self, self.host, self.port);
    }
    dispatch_async(self.socketQueue, ^{
        [self _didReadData];
    });
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (self.isDebug) {
        NSLog(@"DDAsyncSocket -- <%p> host: %@ port: %d did receive data", self, self.host, self.port);
    }
    dispatch_async(self.socketQueue, ^{
        self.isReading = NO;
        
        [self _didReceiveData:data];
        [self _didReadData];
    });
}

@end
