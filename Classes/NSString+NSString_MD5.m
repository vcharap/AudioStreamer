//
//  NSString+NSString_MD5.m
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/26/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "NSString+NSString_MD5.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (NSString_MD5)
-(NSString*)MD5
{
    const char *ptr = [self UTF8String];
    
    unsigned char buffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(ptr, strlen(ptr), buffer);
    
    NSMutableString *str = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++){
        [str appendFormat:@"%02X", buffer[i]];
    }
    
    return [NSString stringWithString:str];
}
@end
