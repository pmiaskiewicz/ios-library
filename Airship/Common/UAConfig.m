/*
 Copyright 2009-2015 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import <objc/runtime.h>

#import "UAConfig+Internal.h"
#import "UAGlobal.h"

@implementation UAConfig

#pragma mark -
#pragma mark Object Lifecycle
- (void)dealloc {

}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.deviceAPIURL = kUAAirshipProductionServer;
        self.analyticsURL = kUAAnalyticsProductionServer;
        self.landingPageContentURL = kUAProductionLandingPageContentURL;
        self.developmentLogLevel = UALogLevelDebug;
        self.productionLogLevel = UALogLevelError;
        self.inProduction = NO;
        self.detectProvisioningMode = NO;
        self.automaticSetupEnabled = YES;
        self.analyticsEnabled = YES;
        self.profilePath = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
        usesProductionPushServer_ = NO;
        self.isSimulator = ([[[UIDevice currentDevice] model] rangeOfString:@"Simulator"].location != NSNotFound);
        self.cacheDiskSizeInMB = 100;
        self.clearUserOnAppRestore = NO;
        self.whitelist = @[];
        self.clearNamedUserOnAppRestore = NO;
        self.channelCaptureEnabled = YES;
        self.customConfig = @{};
        self.channelCreationDelayEnabled = NO;
        self.isDetectProvisioningModeExplicitlySet = NO;
        self.isInProductionExplicitlySet = NO;
    }

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Resolved App Key: %@\n"
            "Resolved App Secret: %@\n"
            "In Production (resolved): %d\n"
            "In Production (as set): %d\n"
            "Development App Key: %@\n"
            "Development App Secret: %@\n"
            "Production App Key: %@\n"
            "Production App Secret: %@\n"
            "Development Log Level: %ld\n"
            "Production Log Level: %ld\n"
            "Resolved Log Level: %ld\n"
            "Detect Provisioning Mode: %d\n"
            "Analytics Enabled: %d\n"
            "Analytics URL: %@\n"
            "Device API URL: %@\n"
            "Cache Size: %ld MB\n"
            "Landing Page Content URL: %@\n"
            "Automatic Setup Enabled: %d\n"
            "Clear user on Application Restore: %d\n"
            "Whitelist: %@\n"
            "Clear named user on App Restore: %d\n"
            "Channel Capture Enabled: %d\n"
            "Custom Config: %@\n"
            "Delay Channel Creation: %d\n",
            self.appKey,
            self.appSecret,
            self.inProduction,
            _inProduction,
            self.developmentAppKey,
            self.developmentAppSecret,
            self.productionAppKey,
            self.productionAppSecret,
            (long)self.developmentLogLevel,
            (long)self.productionLogLevel,
            (long)self.logLevel,
            self.detectProvisioningMode,
            self.analyticsEnabled,
            self.analyticsURL,
            self.deviceAPIURL,
            (unsigned long)self.cacheDiskSizeInMB,
            self.landingPageContentURL,
            self.automaticSetupEnabled,
            self.clearUserOnAppRestore,
            self.whitelist,
            self.clearNamedUserOnAppRestore,
            self.channelCaptureEnabled,
            self.customConfig,
            self.channelCreationDelayEnabled];
}

#pragma mark -
#pragma Factory Methods

+ (instancetype)defaultConfig {
    return [self configWithContentsOfFile:
            [[NSBundle mainBundle] pathForResource:@"AirshipConfig" ofType:@"plist"]];
}

+ (instancetype)configWithContentsOfFile:(NSString *)path {
    UAConfig *config = [self config];
    if (path) {
        //copy from dictionary plist
        NSDictionary *configDict = [[NSDictionary alloc] initWithContentsOfFile:path];
        NSDictionary *normalizedDictionary = [UAConfig normalizeDictionary:configDict];

        [config setValuesForKeysWithDictionary:normalizedDictionary];

        UA_LTRACE(@"Config options: %@", [normalizedDictionary description]);

        // Check if detectProvisioningMode or inProduction were explicity set in AirshipConfig.plist
        config.isDetectProvisioningModeExplicitlySet = [normalizedDictionary objectForKey:@"detectProvisioningMode"] ? YES : NO;
        config.isInProductionExplicitlySet = [normalizedDictionary objectForKey:@"inProduction"] ? YES : NO;
    }
    return config;
}

+ (instancetype)config {
    return [[self alloc] init];
}

#pragma mark -
#pragma Resolved values

- (NSString *)appKey {
    return self.inProduction ? self.productionAppKey : self.developmentAppKey;
}

- (NSString *)appSecret {
    return self.inProduction ? self.productionAppSecret : self.developmentAppSecret;
}

- (UALogLevel)logLevel {
    return self.inProduction ? self.productionLogLevel : self.developmentLogLevel;
}

- (BOOL)isInProduction {
    if (self.isDetectProvisioningModeExplicitlySet || self.isInProductionExplicitlySet) {
        return self.detectProvisioningMode ? [self usesProductionPushServer] : _inProduction;
    } else {
        self.detectProvisioningMode = YES;
        return [self usesProductionPushServer];
    }
}

#pragma mark -
#pragma Data validation
- (BOOL)validate {

    BOOL valid = YES;

    //Check the format of the app key and password.
    //If they're missing or malformed, stop takeoff
    //and prevent the app from connecting to UA.
    NSPredicate *matchPred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^\\S{22}+$"];

    if (![matchPred evaluateWithObject:self.developmentAppKey]) {
        UA_LWARN(@"Development App Key is not valid.");
    }

    if (![matchPred evaluateWithObject:self.developmentAppSecret]) {
        UA_LWARN(@"Development App Secret is not valid.");
    }

    if (![matchPred evaluateWithObject:self.productionAppKey]) {
        UA_LWARN(@"Production App Key is not valid.");
    }

    if (![matchPred evaluateWithObject:self.productionAppSecret]) {
        UA_LWARN(@"Production App Secret is not valid.");
    }

    if (![matchPred evaluateWithObject:self.appKey]) {
        UA_LERR(@"Current App Key (%@) is not valid.", self.appKey);
        valid = NO;
    }

    if (![matchPred evaluateWithObject:self.appSecret]) {
        UA_LERR(@"Current App Secret (%@) is not valid.", self.appSecret);
        valid = NO;
    }

    return valid;
}

+ (NSDictionary *)normalizeDictionary:(NSDictionary *)keyedValues {

    NSDictionary *oldKeyMap = @{@"LOG_LEVEL" : @"developmentLogLevel",
                                @"PRODUCTION_APP_KEY" : @"productionAppKey",
                                @"PRODUCTION_APP_SECRET" : @"productionAppSecret",
                                @"DEVELOPMENT_APP_KEY" : @"developmentAppKey",
                                @"DEVELOPMENT_APP_SECRET" : @"developmentAppSecret",
                                @"APP_STORE_OR_AD_HOC_BUILD" : @"inProduction",
                                @"AIRSHIP_SERVER" : @"deviceAPIURL",
                                @"ANALYTICS_SERVER" : @"analyticsURL"};

    NSMutableDictionary *newKeyedValues = [NSMutableDictionary dictionary];

    for (NSString *key in keyedValues) {
        if (oldKeyMap[key]) {
            UA_LWARN(@"%@ is a legacy config key, use %@ instead", key, oldKeyMap[key]);
        }

        NSString *realKey = [oldKeyMap objectForKey:key] ?: key;
        id value = [keyedValues objectForKey:key];

        // Strip whitespace, if necessary
        if ([value isKindOfClass:[NSString class]]){
            value = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }

        objc_property_t property = class_getProperty(self, [realKey UTF8String]);

        if (property != NULL) {
            NSString *type = [NSString stringWithUTF8String:property_getAttributes(property)];

            if ([type hasPrefix:@"Tc"] || [type hasPrefix:@"TB"]) {//treat chars as bools
                value = [NSNumber numberWithBool:[value boolValue]];
            } else if (![type hasPrefix:@"T@"]) {//indicates an obj-c object (id)
                value = [NSNumber numberWithInt:[value intValue]];
            }
        }

        [newKeyedValues setValue:value forKey:realKey];
    }

    return newKeyedValues;
}

#pragma mark -
#pragma Provisioning Profile Detection

- (BOOL)usesProductionPushServer {

    // only test if a profile is available
    // this is useful for testing/detecting simulator

    dispatch_once(&usesProductionPred_, ^{
        if (self.profilePath) {
            self->usesProductionPushServer_ = [UAConfig isProductionProvisioningProfile:self.profilePath];
        } else if (!self.isSimulator) {
            // This appears to be the case for production apps distributed by the app store.
            // The embedded.mobileprovision is stripped during Apple's re-signing/deployment process.
            UA_LDEBUG(@"No profile found, but not a simulator: inProduction = YES");
            self->usesProductionPushServer_ = YES;
        } else {
            UA_LERR(@"No profile found. Unable to automatically detect provisioning mode in the simulator. Falling back to inProduction as set: %d", self->_inProduction);
            self->usesProductionPushServer_ = self->_inProduction;
        }
    });

    return usesProductionPushServer_;
}

+ (BOOL)isProductionProvisioningProfile:(NSString *)profilePath {

    // Attempt to read this file as ASCII (rather than UTF-8) due to the binary blocks before and after the plist data
    NSError *err = nil;
    NSString *embeddedProfile = [NSString stringWithContentsOfFile:profilePath
                                                          encoding:NSASCIIStringEncoding
                                                             error:&err];
    UA_LTRACE(@"Profile path: %@", profilePath);

    if (err) {
        UA_LERR(@"No mobile provision profile found or the profile could not be read. Defaulting to production mode.");
        return YES;
    }

    NSDictionary *plistDict = nil;
    NSScanner *scanner = [[NSScanner alloc] initWithString:embeddedProfile];

    if ([scanner scanUpToString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" intoString:nil]) {
        NSString *plistString = nil;
        if ([scanner scanUpToString:@"</plist>" intoString:&plistString]) {
            NSData *data = [[plistString stringByAppendingString:@"</plist>"] dataUsingEncoding:NSUTF8StringEncoding];
            plistDict = [NSPropertyListSerialization propertyListWithData:data
                                                                  options:NSPropertyListImmutable
                                                                   format:nil
                                                                    error:nil];
        }
    }

    // Tell the logs a little about the app
    if ([plistDict valueForKeyPath:@"ProvisionedDevices"]){
        if ([[plistDict valueForKeyPath:@"Entitlements.get-task-allow"] boolValue]) {
            UA_LDEBUG(@"Debug provisioning profile. Uses the APNS Sandbox Servers.");
        } else {
            UA_LDEBUG(@"Ad-Hoc provisioning profile. Uses the APNS Production Servers.");
        }
    } else if ([[plistDict valueForKeyPath:@"ProvisionsAllDevices"] boolValue]) {
        UA_LDEBUG(@"Enterprise provisioning profile. Uses the APNS Production Servers.");
    } else {
        UA_LDEBUG(@"App Store provisioning profile. Uses the APNS Production Servers.");
    }

    NSString *apsEnvironment = [plistDict valueForKeyPath:@"Entitlements.aps-environment"];
    UA_LDEBUG(@"APS Environment set to %@", apsEnvironment);
    if ([@"development" isEqualToString:apsEnvironment]) {
        return NO;
    }

    // Let the dev know if there's not an APS entitlement in the profile. Something is terribly wrong.
    if (!apsEnvironment) {
        UA_LERR(@"aps-environment value is not set. If this is not a simulator, ensure that the app is properly provisioned for push");
    }

    return YES;// For safety, assume production unless the profile is explicitly set to development
}

- (void)setAnalyticsURL:(NSString *)analyticsURL {
    //Any appending url starts with a beginning /, so make sure the base url does not
    if ([analyticsURL hasSuffix:@"/"]) {
        UA_LWARN(@"Analytics URL ends with a trailing slash, stripping ending slash.");
        _analyticsURL = [analyticsURL substringWithRange:NSMakeRange(0, [analyticsURL length] - 1)];
    } else {
        _analyticsURL = [analyticsURL copy];
    }
}

- (void)setDeviceAPIURL:(NSString *)deviceAPIURL {
    //Any appending url starts with a beginning /, so make sure the base url does not
    if ([deviceAPIURL hasSuffix:@"/"]) {
        UA_LWARN(@"Device API URL ends with a trailing slash, stripping ending slash.");
        _deviceAPIURL = [deviceAPIURL substringWithRange:NSMakeRange(0, [deviceAPIURL length] - 1)];
    } else {
        _deviceAPIURL = [deviceAPIURL copy];
    }
}

- (void)setLandingPageContentURL:(NSString *)landingPageContentURL {
    //Any appending url starts with a beginning /, so make sure the base url does not
    if ([landingPageContentURL hasSuffix:@"/"]) {
        UA_LWARN(@"Landing page content URL ends with a trailing slash, stripping ending slash.");
        _landingPageContentURL = [landingPageContentURL substringWithRange:NSMakeRange(0, [landingPageContentURL length] - 1)];
    } else {
        _landingPageContentURL = [landingPageContentURL copy];
    }
}

#pragma mark -
#pragma KVC Overrides
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    // Be leniant and no-op for other undefined keys
    // The `super` implementation throws an exception. We'll just log.
    UA_LDEBUG(@"Ignoring invalid UAConfig key: %@", key);
}

@end
