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

- (void)create:(NSDictionary *)config
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject
{
  [_bridge create:config completion:^(NSString *sessionId, NSError *error) {
    if (error) { [self reject:reject with:error]; } else { resolve(sessionId); }
  }];
}

- (void)login:(NSString *)sessionId
   disclosure:(NSDictionary *)disclosure
      resolve:(RCTPromiseResolveBlock)resolve
       reject:(RCTPromiseRejectBlock)reject
{
  [_bridge login:sessionId disclosure:disclosure completion:^(NSError *error) {
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
// Transport/Policy text in userInfo["text"].
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
