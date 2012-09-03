//
//  NSArray+NSArray_FirstObject.m
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/26/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "NSArray+NSArray_FirstObject.h"

@implementation NSArray (NSArray_FirstObject)
-(id)firstObject
{
    id obj = nil;
    if([self count]){
        obj = [self objectAtIndex:0];
    }
    return obj;
}
@end
