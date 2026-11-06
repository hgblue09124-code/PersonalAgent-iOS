#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PAPythonRuntimeBridge : NSObject

+ (BOOL)initializeRuntimeWithError:(NSError * _Nullable * _Nullable)error;

+ (nullable NSString *)planRequestWithText:(NSString *)text
                           allowedSkillIDs:(NSArray<NSString *> *)allowedSkillIDs
                                     error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
