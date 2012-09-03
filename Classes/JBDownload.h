//
//  JBDownload.h
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString* const JBDownloadErrorDomain;

extern NSString* const JBDownloadOptionsFileOffsetKey;

extern NSString* const JBDownloadErrorNotification;
extern NSString* const JBDownloadWriteSuccessfulNotification;

extern NSString* const JBDownloadWriteSuccessfulBytesWrittenKey;
extern NSString* const JBDownloadErrorNotificationErrorTypeKey;
extern NSString* const JBDownloadErrorNotificationExceptionKey;

extern NSString* const JBDownloadError_Exception;

//extern NSString* const JBDownloadErrorNotification

typedef enum
{
    JBDownload_State_INIT,
    JBDownload_State_STREAM_OPEN,
    JBDownload_State_STREAMING,
    JBDownload_State_STREAM_EOF,
    JBDownload_State_USER_STOP,
    //JBDownload_State_FINISHED,
    JBDownload_State_ERROR
    
} JBDownload_State;

typedef enum 
{
    JBDownload_Error_NETWORK = 1,
    JBDownload_Error_STREAM,
    JBDownload_Error_HTTP,
    JBDownload_Error_FILE,
    
} JBDownload_Error;

typedef enum
{
    JBDownload_NETWORK_OFFLINE = 1,
    JBDownload_NETWORK_CONNECTION_FAILED,
    
    JBDownload_STREAM_OPEN_ERR = 50,
    JBDownload_STREAM_SETPROP_ERR,
    JBDownload_STREAM_RECONNECT_FAILED,
    JBDownload_STREAM_UNCLASSIFIED_ERROR,
    
    JBDownload_HTTP_AUTH_FAILED = 100,
    JBDownload_HTTP_NOT_FOUND,
    JBDownload_HTTP_4xx_ERROR,
    
    JBDownload_WRITE_EXCEPTION = 200,
    JBDownload_FILE_MISSING
    
} JBDownload_Error_Code;

@interface JBDownload : NSObject
{
    NSURLRequest *_request;
    NSString* _filePath;
    NSFileHandle *_fileWriter;
    NSUInteger _bytesWritten;
    NSDictionary* _headers;
    NSDictionary *_options;
    
    dispatch_queue_t _writeQueue;
    
    JBDownload_State _state;
    JBDownload_Error _error;
    JBDownload_Error_Code _code;
    NSInteger _retryCount;
    CFReadStreamRef _stream;
    NSDictionary *_httpHeaders;
    NSUInteger _bytesRead;
}

@property (readonly) JBDownload_State state;
@property (readonly) JBDownload_Error error;
@property (readonly) JBDownload_Error_Code code;
@property (readonly) NSUInteger bytesWritten;

@property NSUInteger bytesRead;

@property (strong, readonly) NSDictionary* headers;

-(id)initWithURLRequest:(NSURLRequest*)request filePath:(NSString*)filePath options:(NSDictionary*)options;
-(id)initAsyncWithURLRequest:(NSURLRequest*)request filePath:(NSString*)filePath options:(NSDictionary*)options writeQueue:(dispatch_queue_t)writeQueue;
-(BOOL)start;
-(void)stop;
//-(void)pause;

-(NSUInteger)bytesWritten;

@end
