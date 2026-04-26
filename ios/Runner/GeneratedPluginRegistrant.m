//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<flutter_local_notifications/FlutterLocalNotificationsPlugin.h>)
#import <flutter_local_notifications/FlutterLocalNotificationsPlugin.h>
#else
@import flutter_local_notifications;
#endif

#if __has_include(<google_mlkit_commons/GoogleMlKitCommonsPlugin.h>)
#import <google_mlkit_commons/GoogleMlKitCommonsPlugin.h>
#else
@import google_mlkit_commons;
#endif

#if __has_include(<google_mlkit_digital_ink_recognition/GoogleMlKitDigitalInkRecognitionPlugin.h>)
#import <google_mlkit_digital_ink_recognition/GoogleMlKitDigitalInkRecognitionPlugin.h>
#else
@import google_mlkit_digital_ink_recognition;
#endif

#if __has_include(<google_mlkit_text_recognition/GoogleMlKitTextRecognitionPlugin.h>)
#import <google_mlkit_text_recognition/GoogleMlKitTextRecognitionPlugin.h>
#else
@import google_mlkit_text_recognition;
#endif

#if __has_include(<path_provider_foundation/PathProviderPlugin.h>)
#import <path_provider_foundation/PathProviderPlugin.h>
#else
@import path_provider_foundation;
#endif

#if __has_include(<permission_handler_apple/PermissionHandlerPlugin.h>)
#import <permission_handler_apple/PermissionHandlerPlugin.h>
#else
@import permission_handler_apple;
#endif

#if __has_include(<printing/PrintingPlugin.h>)
#import <printing/PrintingPlugin.h>
#else
@import printing;
#endif

#if __has_include(<receive_sharing_intent/ReceiveSharingIntentPlugin.h>)
#import <receive_sharing_intent/ReceiveSharingIntentPlugin.h>
#else
@import receive_sharing_intent;
#endif

#if __has_include(<share_plus/FPPSharePlusPlugin.h>)
#import <share_plus/FPPSharePlusPlugin.h>
#else
@import share_plus;
#endif

#if __has_include(<speech_to_text/SpeechToTextPlugin.h>)
#import <speech_to_text/SpeechToTextPlugin.h>
#else
@import speech_to_text;
#endif

#if __has_include(<sqflite_darwin/SqflitePlugin.h>)
#import <sqflite_darwin/SqflitePlugin.h>
#else
@import sqflite_darwin;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FlutterLocalNotificationsPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterLocalNotificationsPlugin"]];
  [GoogleMlKitCommonsPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitCommonsPlugin"]];
  [GoogleMlKitDigitalInkRecognitionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitDigitalInkRecognitionPlugin"]];
  [GoogleMlKitTextRecognitionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitTextRecognitionPlugin"]];
  [PathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"PathProviderPlugin"]];
  [PermissionHandlerPlugin registerWithRegistrar:[registry registrarForPlugin:@"PermissionHandlerPlugin"]];
  [PrintingPlugin registerWithRegistrar:[registry registrarForPlugin:@"PrintingPlugin"]];
  [ReceiveSharingIntentPlugin registerWithRegistrar:[registry registrarForPlugin:@"ReceiveSharingIntentPlugin"]];
  [FPPSharePlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPSharePlusPlugin"]];
  [SpeechToTextPlugin registerWithRegistrar:[registry registrarForPlugin:@"SpeechToTextPlugin"]];
  [SqflitePlugin registerWithRegistrar:[registry registrarForPlugin:@"SqflitePlugin"]];
}

@end
