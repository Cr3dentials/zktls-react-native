#import "ZktlsReactNative.h"
#import "ZktlsReactNative-Swift.h"
#import <React/RCTBridgeModule.h>

@implementation ZktlsReactNative {
  ZktlsBridge *_bridge;
}

- (instancetype)init
{
  if (self = [super init]) {
    _bridge = [ZktlsBridge new];
    __weak __typeof(self) weakSelf = self;
    _bridge.onProgress = ^(NSString *sessionId, NSString *phase, NSInteger percent) {
      [weakSelf emitOnProgress:@{
        @"sessionId": sessionId,
        @"phase": phase,
        @"percent": @(percent),
      }];
    };
  }
  return self;
}

// Codegen types the object params as C++ structs wrapping the JS object (see the
// generated ZktlsReactNativeSpec.h). Flatten them back to the NSDictionary the Swift
// bridge reads.
- (void)create:(JS::NativeZktlsReactNative::SessionConfig &)config
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject
{
  NSDictionary *dict = @{
    @"baseUrl": config.baseUrl() ?: @"",
    @"appCredential": config.appCredential() ?: @"",
    @"userIdHash": config.userIdHash() ?: @"",
    @"profileId": config.profileId() ?: @"",
    @"policyId": config.policyId() ?: @"",
    @"idempotencyKey": config.idempotencyKey() ?: @"",
    @"clientRegion": config.clientRegion() ?: @"",
    @"networkKey": config.networkKey() ?: @"",
    @"trustBundleJson": config.trustBundleJson() ?: @"",
    @"trustBundleUrl": config.trustBundleUrl() ?: @"",
    @"trustOperatorKey": config.trustOperatorKey() ?: @"",
    @"policyBundleJson": config.policyBundleJson() ?: @"",
    @"policyBundleDigest": config.policyBundleDigest() ?: @"",
  };
  [_bridge create:dict completion:^(NSString *sessionId, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(sessionId); }
  }];
}

- (void)login:(NSString *)sessionId
   disclosure:(JS::NativeZktlsReactNative::Disclosure &)disclosure
      resolve:(RCTPromiseResolveBlock)resolve
       reject:(RCTPromiseRejectBlock)reject
{
  // All four fields are optional; include only the ones JS actually sent.
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  if (disclosure.title()) d[@"title"] = disclosure.title();
  if (disclosure.message()) d[@"message"] = disclosure.message();
  if (disclosure.accept()) d[@"accept"] = disclosure.accept();
  if (disclosure.decline()) d[@"decline"] = disclosure.decline();
  [_bridge login:sessionId disclosure:d completion:^(NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(nil); }
  }];
}

- (void)capture:(NSString *)sessionId
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject
{
  [_bridge capture:sessionId completion:^(NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(nil); }
  }];
}

- (void)prove:(NSString *)sessionId
      resolve:(RCTPromiseResolveBlock)resolve
       reject:(RCTPromiseRejectBlock)reject
{
  [_bridge prove:sessionId completion:^(NSDictionary *report, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(report); }
  }];
}

- (void)claim:(NSString *)sessionId
      resolve:(RCTPromiseResolveBlock)resolve
       reject:(RCTPromiseRejectBlock)reject
{
  [_bridge claim:sessionId completion:^(NSDictionary *claim, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(claim); }
  }];
}

- (void)configure:(NSString *)appKey
            theme:(JS::NativeZktlsReactNative::Theme &)theme
          strings:(NSDictionary *)strings
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject
{
  // Every theme field is optional; include only the ones JS actually sent.
  NSMutableDictionary *t = [NSMutableDictionary dictionary];
  if (theme.accent()) t[@"accent"] = theme.accent();
  if (theme.background()) t[@"background"] = theme.background();
  if (theme.text()) t[@"text"] = theme.text();
  if (theme.logo()) t[@"logo"] = theme.logo();
  [_bridge configure:appKey theme:t strings:strings completion:^(NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(nil); }
  }];
}

- (void)verify:(NSArray *)platforms
     reference:(NSString *)reference
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject
{
  [_bridge verify:platforms reference:reference completion:^(NSDictionary *outcome, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(outcome); }
  }];
}

- (void)verifyToken:(NSString *)token
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject
{
  [_bridge verifyToken:token completion:^(NSDictionary *outcome, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(outcome); }
  }];
}

- (void)cancel:(NSString *)sessionId
{
  [_bridge cancel:sessionId];
}

- (void)dispose:(NSString *)sessionId
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject
{
  [_bridge dispose:sessionId completion:^(NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(nil); }
  }];
}

// The Swift side puts the JS error code in userInfo["code"] and the
// Transport/Policy/Refused text in userInfo["text"]; userInfo reaches JS.
- (void)reject:(RCTPromiseRejectBlock)reject with:(NSError *)error
{
  NSString *code = error.userInfo[@"code"] ?: @"Internal";
  NSString *message = error.userInfo[@"text"] ?: code;
  reject(code, message, error);
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeZktlsReactNativeSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"ZktlsReactNative";
}

@end
