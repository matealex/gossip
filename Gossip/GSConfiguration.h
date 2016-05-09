//
//  GSConfiguration.h
//  Gossip
//
//  Created by Chakrit Wichian on 7/6/12.
//

#import <Foundation/Foundation.h>
#import "GSAccountConfiguration.h"


/// Supported transport types.
typedef enum {
    GSUDPTransportType, ///< UDP transport type.
    GSUDP6TransportType, ///< UDP on IPv6 transport type.
    GSTCPTransportType, ///< TCP transport type.
    GSTCP6TransportType, ///< TCP on IPv6 transport type.
    GSTLSTransportType, /// TLS transport type.
    GSTLS6TransportType /// TLS on IPv6 transport type.
} GSTransportType;

typedef enum {
    GSQOSTypeBestEffort,
    GSQOSTypeBackground,
    GSQOSTypeVideo,
    GSQOSTypeVoice,
    GSQOSTypeControl
} GSQosType;


/// Main class for configuring a SIP user agent.
@interface GSConfiguration : NSObject <NSCopying>

@property (nonatomic) unsigned int logLevel; ///< PJSIP log level.
@property (nonatomic) unsigned int consoleLogLevel; ///< PJSIP console output level.

@property (nonatomic) GSTransportType transportType; ///< Transport type to use for connection.
@property (nonatomic) GSQosType qosType; ///< QOS type used for connection.

@property (nonatomic) unsigned int clockRate; ///< PJSIP clock rate.
@property (nonatomic) unsigned int soundClockRate; ///< PJSIP sound clock rate.
@property (nonatomic) float volumeScaleTx; ///< Used for scaling volumes up and down.
@property (nonatomic) float volumeScaleRx; ///< Used for scaling volumes up and down.
@property (nonatomic) BOOL enableSRV; ///< Sets DNS to use 8.8.8.8 - beware if the carrier blocks this

@property (nonatomic) unsigned int echoCancelationTail;

@property (nonatomic, strong) GSAccountConfiguration *account;

+ (id)defaultConfiguration;
+ (id)configurationWithConfiguration:(GSConfiguration *)configuration;

@end
