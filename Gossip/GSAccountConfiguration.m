//
//  GSAccountConfiguration.m
//  Gossip
//
//  Created by Chakrit Wichian on 7/6/12.
//

#import "GSAccountConfiguration.h"


@implementation GSAccountConfiguration

+ (id)defaultConfiguration {
    return [[self alloc] init];
}

+ (id)configurationWithConfiguration:(GSAccountConfiguration *)configuration {
    return [configuration copy];
}


- (id)init {
    if (!(self = [super init]))
        return nil; // super init failed.
    
    _address = nil;
    _domain = nil;
    _proxyServer = nil;
    _authScheme = @"digest";
    _authRealm = @"*";
    _username = nil;
    _password = nil;
    _userAgent = nil;
    _useipv6 = NO;

    _enableRingback = YES;
    _ringbackFilename = @"ringtone.wav";
    
    _useRfc5626 = YES;

    // can prevent registration for services which don't support it so NO by default.
    _enableStatusPublishing = NO;
    return self;
}

- (void)dealloc {
    _address = nil;
    _domain = nil;
    _proxyServer = nil;
    _authScheme = nil;
    _authRealm = nil;
    _username = nil;
    _password = nil;
    _userAgent = nil;
    _ringbackFilename = nil;
    _registrationTimeout = nil;
}


- (id)copyWithZone:(NSZone *)zone {
    GSAccountConfiguration *replica = [GSAccountConfiguration defaultConfiguration];
    
    replica.address = self.address;
    replica.domain = self.domain;
    replica.proxyServer = self.proxyServer;
    replica.authScheme = self.authScheme;
    replica.authRealm = self.authRealm;
    replica.username = self.username;
    replica.password = self.password;
    replica.userAgent = self.userAgent;
    replica.useipv6 = self.useipv6;

    replica.registrationTimeout = self.registrationTimeout;

    replica.enableStatusPublishing = self.enableStatusPublishing;

    replica.enableRingback = self.enableRingback;
    replica.ringbackFilename = self.ringbackFilename;
    replica.useRfc5626 = self.useRfc5626;

    return replica;
}

@end
