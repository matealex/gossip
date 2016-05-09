//
//  GSAccount.m
//  Gossip
//
//  Created by Chakrit Wichian on 7/6/12.
//

#import "GSAccount.h"
#import "GSAccount+Private.h"
#import "GSCall.h"
#import "GSDispatch.h"
#import "GSUserAgent.h"
#import "PJSIP.h"
#import "Util.h"

static pjsip_transport *the_transport;

@interface GSAccount()
@property(nonatomic,strong) NSString *statusText;
@end

@implementation GSAccount {
    GSAccountConfiguration *_config;
    NSDate *_registrationExpiration;
    BOOL isChangingIP;
    int transportReferenceCount;
}

- (id)init {
    if (self = [super init]) {
        _accountId = PJSUA_INVALID_ID;
        _status = GSAccountStatusOffline;
        _registrationExpiration = nil;
        _config = nil;
        isChangingIP = NO;
        _delegate = nil;
        transportReferenceCount = 0;
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self
                   selector:@selector(didReceiveIncomingCall:)
                       name:GSSIPIncomingCallNotification
                     object:[GSDispatch class]];
        [center addObserver:self
                   selector:@selector(registrationDidStart:)
                       name:GSSIPRegistrationDidStartNotification
                     object:[GSDispatch class]];
        [center addObserver:self
                   selector:@selector(registrationStateDidChange:)
                       name:GSSIPRegistrationStateDidChangeNotification
                     object:[GSDispatch class]];
        [center addObserver:self
                   selector:@selector(transportStateDidChange:)
                       name:GSSIPTransportStateDidChangeNotification
                     object:[GSDispatch class]];
        [center addObserver:self
                   selector:@selector(didReceiveMwiNotification:)
                       name:GSSIPMwiInfoNotification
                     object:[GSDispatch class]];
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];

    GSUserAgent *agent = [GSUserAgent sharedAgent];
    if (_accountId != PJSUA_INVALID_ID && [agent status] != GSUserAgentStateDestroyed) {
        if (pjsua_acc_is_valid(_accountId)) {
            GSLogIfFails(pjsua_acc_del(_accountId));
        }
        _accountId = PJSUA_INVALID_ID;
    }

    _accountId = PJSUA_INVALID_ID;
    _config = nil;
}


- (GSAccountConfiguration *)configuration {
    return _config;
}

- (NSDate*)registrationExpiration{
    return _registrationExpiration;
}

- (BOOL)configure:(GSAccountConfiguration *)configuration {
    _config = [configuration copy];
    
    // prepare account config
    pjsua_acc_config accConfig;
    pjsua_acc_config_default(&accConfig);
    accConfig.reg_retry_interval = 10;
    accConfig.reg_first_retry_interval = 2;
    
    accConfig.id = [GSPJUtil PJAddressWithString:_config.address];
    accConfig.reg_uri = [GSPJUtil PJAddressWithString:_config.domain];
    accConfig.register_on_acc_add = PJ_FALSE; // connect manually
    accConfig.publish_enabled = _config.enableStatusPublishing ? PJ_TRUE : PJ_FALSE;
    
    if (!_config.proxyServer) {
        accConfig.proxy_cnt = 0;
    } else {
        accConfig.proxy_cnt = 1;
        accConfig.proxy[0] = [GSPJUtil PJAddressWithString:_config.proxyServer];
    }
    
    // adds credentials info
    pjsip_cred_info creds;
    creds.scheme = [GSPJUtil PJStringWithString:_config.authScheme];
    creds.realm = [GSPJUtil PJStringWithString:_config.authRealm];
    creds.username = [GSPJUtil PJStringWithString:_config.username];
    creds.data = [GSPJUtil PJStringWithString:_config.password];
    creds.data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    
    accConfig.cred_count = 1;
    accConfig.cred_info[0] = creds;
    accConfig.reg_timeout = [configuration.registrationTimeout intValue];

    // TROY - CT - Allow setting of this by the caller
    accConfig.use_rfc5626 = _config.useRfc5626;

    // finish
    GSReturnNoIfFails(pjsua_acc_add(&accConfig, PJ_TRUE, &_accountId));    
    return YES;
}


- (BOOL)connect {
    NSAssert(!!_config, @"GSAccount not configured.");

    GSReturnNoIfFails(pjsua_acc_set_registration(_accountId, PJ_TRUE));
    GSReturnNoIfFails(pjsua_acc_set_online_status(_accountId, PJ_TRUE));    
    return YES;
}

- (BOOL)disconnect {
    NSAssert(!!_config, @"GSAccount not configured.");
    if (self.status == GSAccountStatusConnected) {
        GSReturnNoIfFails(pjsua_acc_set_online_status(_accountId, PJ_FALSE));
        GSReturnNoIfFails(pjsua_acc_set_registration(_accountId, PJ_FALSE));
    }

    return YES;
}

- (void)startKeepAlive{
    pjsua_acc_set_online_status(_accountId, PJ_TRUE);
}

-(void)performKeepAlive{
    pj_thread_sleep(5000);
}


- (void)setStatus:(GSAccountStatus)newStatus {
    if (_status == newStatus) // don't send KVO notices unless it really changes.
        return;
    
    _status = newStatus;
}


- (void)didReceiveIncomingCall:(NSNotification *)notif {
    pjsua_acc_id accountId = GSNotifGetInt(notif, GSSIPAccountIdKey);
    pjsua_call_id callId = GSNotifGetInt(notif, GSSIPCallIdKey);
    pjsip_rx_data * data = GSNotifGetPointer(notif, GSSIPDataKey);

    if (accountId == PJSUA_INVALID_ID || accountId != _accountId)
        return;
    
    __block GSAccount *self_ = self;
    __block id delegate_ = _delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        GSCall *call = [GSCall incomingCallWithId:callId toAccount:self_];
        if (![delegate_ respondsToSelector:@selector(account:didReceiveIncomingCall:withMessage:)])
            return; // call is disposed/hungup on dealloc
        NSString *msgString = nil;
        if (data->msg_info.msg_buf) {
            msgString = [NSString stringWithUTF8String:data->msg_info.msg_buf];
        }
        [delegate_ account:self didReceiveIncomingCall:call withMessage:msgString];
        
    });
}

- (void)registrationDidStart:(NSNotification *)notif {
    pjsua_acc_id accountId = GSNotifGetInt(notif, GSSIPAccountIdKey);
    pjsua_reg_info * regInfo = GSNotifGetPointer(notif, GSSIPRegInfoKey);
    if (accountId == PJSUA_INVALID_ID || accountId != _accountId)
        return;
    
    struct pjsip_regc_cbparam *rp = regInfo->cbparam;

    if (rp != NULL && the_transport != rp->rdata->tp_info.transport) {
        /* Registration success */
        if (the_transport) {
            pjsip_transport_dec_ref(the_transport);
            the_transport = NULL;
        }
        /* Save transport instance so that we can close it later when
         * new IP address is detected.
         */
        the_transport = rp->rdata->tp_info.transport;
        pjsip_transport_add_ref(the_transport);
    }

    GSAccountStatus accStatus = 0;
    accStatus = regInfo->renew ? GSAccountStatusConnecting : GSAccountStatusDisconnecting;

    __block id self_ = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [self_ setStatus:accStatus]; });
}

- (void)registrationStateDidChange:(NSNotification *)notif {
    pjsua_acc_id accountId = GSNotifGetInt(notif, GSSIPAccountIdKey);
    pjsua_reg_info * regInfo = GSNotifGetPointer(notif, GSSIPRegInfoKey);
    struct pjsip_regc_cbparam *rp = regInfo->cbparam;

    if (accountId == PJSUA_INVALID_ID || accountId != _accountId)
        return;
    
    GSAccountStatus accStatus;
    
    pjsua_acc_info info;
    GSReturnIfFails(pjsua_acc_get_info(accountId, &info));
    self.statusText = [[GSPJUtil stringWithPJString:&info.status_text] copy];

    if (info.reg_last_err != PJ_SUCCESS) {
        accStatus = GSAccountStatusInvalid;
        
    } else {
        pjsip_status_code code = info.status;
        if (code == 0 || (info.online_status == PJ_FALSE)) {
            accStatus = GSAccountStatusOffline;
            if (isChangingIP) {
                isChangingIP = NO;
                dispatch_after(1, dispatch_get_main_queue(), ^{
                    [self connect];
                });
            }
        } else if (PJSIP_IS_STATUS_IN_CLASS(code, 100) || PJSIP_IS_STATUS_IN_CLASS(code, 300)) {
            accStatus = GSAccountStatusConnecting;
        } else if (PJSIP_IS_STATUS_IN_CLASS(code, 200)) {
            accStatus = GSAccountStatusConnected;

        } else {
            if (code == 408) {
                [self connect];
            }
            accStatus = GSAccountStatusInvalid;
        }
    }

    if (rp->code/100 == 2 && rp->expiration > 0 && rp->contact_cnt > 0) {
        /* We already saved the transport instance */
    } else {
        if (the_transport) {
            pjsip_transport_dec_ref(the_transport);
            the_transport = NULL;
        }
    }
    
    __block id self_ = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [self_ setStatus:accStatus]; });
}

- (BOOL)handleIPChange{
    if (self.status == GSAccountStatusOffline) {
        return NO;
    }

    isChangingIP = YES;

    if (the_transport) {
        GSReturnNoIfFails(pjsip_transport_shutdown(the_transport));
        pjsip_transport_dec_ref(the_transport);
        the_transport = NULL;
    }

    return [self disconnect];
}

- (void)transportStateDidChange:(NSNotification *)notif {
    pjsip_transport_state state = GSNotifGetInt(notif, GSSIPTransportStateKey);
    pjsip_transport *tp = GSNotifGetPointer(notif, GSSIPTransportKey);

    if (state == PJSIP_TP_STATE_DISCONNECTED && the_transport == tp) {
        pjsip_transport_dec_ref(the_transport);
        the_transport = NULL;
    }
}

- (void)didReceiveMwiNotification:(NSNotification *)notif {
    __block GSAccount *self_ = self;
    __block id delegate_ = _delegate;

    NSString *msgData = notif.userInfo[GSMsgInfoStringKey];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (![delegate_ respondsToSelector:@selector(accountDidReceiveMwiNotification:msgData:)])
            return; // call is disposed/hungup on dealloc
        [delegate_ accountDidReceiveMwiNotification:self_ msgData:msgData];
    });
}

@end
