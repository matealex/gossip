//
//  GSDispatch.m
//  Gossip
//
//  Created by Chakrit Wichian on 7/6/12.
//

#import "GSDispatch.h"


void onRegistrationStarted(pjsua_acc_id accountId, pjsua_reg_info *info);
void onRegistrationState(pjsua_acc_id accountId, pjsua_reg_info *info);
void onTransportState(pjsip_transport *tp, pjsip_transport_state state, const pjsip_transport_state_info *info);
void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata);
void onCallMediaState(pjsua_call_id callId);
void onCallState(pjsua_call_id callId, pjsip_event *e);
void onMwiInfo(pjsua_acc_id accountId, pjsua_mwi_info *mwiInfo);


static dispatch_queue_t _queue = NULL;


@implementation GSDispatch

+ (void)initialize {
    _queue = dispatch_queue_create("GSDispatch", DISPATCH_QUEUE_SERIAL);
}

+ (void)configureCallbacksForAgent:(pjsua_config *)uaConfig {
    uaConfig->cb.on_reg_started2 = &onRegistrationStarted;
    uaConfig->cb.on_reg_state2 = &onRegistrationState;
    uaConfig->cb.on_transport_state = &onTransportState;
    uaConfig->cb.on_incoming_call = &onIncomingCall;
    uaConfig->cb.on_call_media_state = &onCallMediaState;
    uaConfig->cb.on_call_state = &onCallState;
    uaConfig->cb.on_mwi_info = &onMwiInfo;
}


#pragma mark - Dispatch sink

// TODO: May need to implement some form of subscriber filtering
//   orthogonaly/globally if we're to scale. But right now a few
//   dictionary lookups on the receiver side probably wouldn't hurt much.

+ (void)dispatchRegistrationStarted:(pjsua_acc_id)accountId registrationInfo:(pjsua_reg_info *)regInfo {
    NSLog(@"Gossip: dispatchRegistrationStarted(%d)", accountId);
    
    NSDictionary *info = nil;
    info = @{GSSIPAccountIdKey : [NSNumber numberWithInt:accountId] ,
             GSSIPRegInfoKey : [NSValue valueWithPointer:regInfo]};
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPRegistrationDidStartNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchRegistrationState:(pjsua_acc_id)accountId registrationInfo:(pjsua_reg_info *)regInfo{
    NSLog(@"Gossip: dispatchRegistrationState(%d)", accountId);
    
    NSDictionary *info = nil;
    info = @{GSSIPAccountIdKey : [NSNumber numberWithInt:accountId] ,
             GSSIPRegInfoKey : [NSValue valueWithPointer:regInfo]};

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPRegistrationStateDidChangeNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchTransportState:(pjsip_transport*)transport state:(pjsip_transport_state)state info:(const pjsip_transport_state_info *)transportInfo{
    NSDictionary *info = nil;

    info = @{GSSIPTransportInfoKey : [NSValue valueWithPointer:transportInfo],
             GSSIPTransportKey : [NSValue valueWithPointer:transport],
             GSSIPTransportStateKey : [NSNumber numberWithInt:state]};

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPTransportStateDidChangeNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchIncomingCall:(pjsua_acc_id)accountId
                      callId:(pjsua_call_id)callId
                        data:(pjsip_rx_data *)data {
    NSLog(@"Gossip: dispatchIncomingCall(%d, %d)", accountId, callId);
    
    NSDictionary *info = nil;
    info = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:accountId], GSSIPAccountIdKey,
            [NSNumber numberWithInt:callId], GSSIPCallIdKey,
            [NSValue valueWithPointer:data], GSSIPDataKey, nil];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPIncomingCallNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchCallMediaState:(pjsua_call_id)callId {
    NSLog(@"Gossip: dispatchCallMediaState(%d)", callId);
    
    NSDictionary *info = nil;
    info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:callId]
                                       forKey:GSSIPCallIdKey];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPCallMediaStateDidChangeNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchCallState:(pjsua_call_id)callId event:(pjsip_event *)e {
    NSLog(@"Gossip: dispatchCallState(%d)", callId);

    NSDictionary *info = nil;
    info = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:callId], GSSIPCallIdKey,
            [NSValue valueWithPointer:e], GSSIPDataKey, nil];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPCallStateDidChangeNotification
                          object:self
                        userInfo:info];
}

+ (void)dispatchMwiInfo:(pjsua_mwi_info *)info accountId:(pjsua_acc_id)accountId {
    NSLog(@"Gossip: dispatchMwiInfo(%d)", accountId);

    NSDictionary *dict = @{GSSIPAccountIdKey:@(accountId),
                           GSSIPDataKey:[NSValue valueWithPointer:info->rdata],
                           GSMsgInfoStringKey:[NSString stringWithUTF8String:info->rdata->msg_info.msg_buf]};

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:GSSIPMwiInfoNotification
                          object:self
                        userInfo:dict];
}

@end


#pragma mark - C event bridge

// Bridge C-land callbacks to ObjC-land.

static inline void dispatch(dispatch_block_t block) {    
    // autorelease here since events wouldn't be triggered that often.
    // + GCD autorelease pool do not have drainage time guarantee (== possible mem headaches).
    // See the "Implementing tasks using blocks" section for more info
    // REF: http://developer.apple.com/library/ios/#documentation/General/Conceptual/ConcurrencyProgrammingGuide/OperationQueues/OperationQueues.html
    @autoreleasepool {

        // NOTE: Needs to use dispatch_sync() instead of dispatch_async() because we do not know
        //   the lifetime of the stuff being given to us by PJSIP (e.g. pjsip_rx_data*) so we
        //   must process it completely before the method ends.
        dispatch_sync(_queue, block);
    }
}

void onRegistrationStarted(pjsua_acc_id accountId, pjsua_reg_info *info) {
    dispatch(^{ [GSDispatch dispatchRegistrationStarted:accountId registrationInfo:info];});
}

void onRegistrationState(pjsua_acc_id accountId, pjsua_reg_info *info) {
    dispatch(^{ [GSDispatch dispatchRegistrationState:accountId registrationInfo:info];});
}

void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata) {
    dispatch(^{ [GSDispatch dispatchIncomingCall:accountId callId:callId data:rdata]; });
}

void onCallMediaState(pjsua_call_id callId) {
    dispatch(^{ [GSDispatch dispatchCallMediaState:callId]; });
}

void onCallState(pjsua_call_id callId, pjsip_event *e) {
    dispatch(^{ [GSDispatch dispatchCallState:callId event:e]; });
}

void onTransportState(pjsip_transport *tp, pjsip_transport_state state, const pjsip_transport_state_info *info){
    dispatch(^{ [GSDispatch dispatchTransportState:tp state:state info:info]; });
}

void onMwiInfo(pjsua_acc_id accountId, pjsua_mwi_info *mwiInfo) {
    dispatch(^{ [GSDispatch dispatchMwiInfo:mwiInfo accountId:accountId]; });
}
