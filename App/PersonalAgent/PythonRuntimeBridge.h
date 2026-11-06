#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PAPythonRuntimeBridge : NSObject

+ (BOOL)initializeRuntimeWithErrorMessage:(NSString * _Nullable * _Nullable)errorMessage;

+ (nullable NSString *)planRequestWithText:(NSString *)text
                           allowedSkillIDs:(NSArray<NSString *> *)allowedSkillIDs
                              errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
