DDTCPClient
==

DDTCPClient is a high level socket util based on [CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket).

## Features

* Thread safety, socket operations is on serial queue.
* Subcontracting and Sticky bag.
* Maintain read package one.
* Network state monitoring and reconnection mechanism.
* Heartbeat mechanism.

## Installation

### CocoaPods

1. Add `pod 'DDTCPClient'` to your Podfile.
2. Run `pod install` or `pod update`.
3. Import \<DDTCPClient/DDTCPClient.h\>.

### Manually

1. Download all the files in the Source subdirectory.
2. Add the source files to your Xcode project.
3. Import `DDTCPClient.h`.

## Usage

### Initialization 

```objc
    DDTCPClient *socket = [[DDTCPClient alloc] init];
    socket.delegate = self;
```
### Connect and disconnect

```objc
    // Connect
    [socket connectHost:host port:port];
    
    // Disconnect
    [socket disConnect];
```
### Sent heart or send data

```objc
    // Send data
    NSString *registStr = @"I'm register informations";
    NSData *registData = [registStr dataUsingEncoding:NSUTF8StringEncoding];
    
    [socket sendData:registData];

    // Sent heart, just set once, heart data will be send one by one
    NSString *heartStr = @"I'm heart informations";
    NSData *heartData = [heartStr dataUsingEncoding:NSUTF8StringEncoding];
    
    [socket setHeartData:heartData];
```

Requirements
==============
This library requires `iOS 8.0+`.


License
==============
DDTCPClient is provided under the MIT license. See LICENSE file for details.
