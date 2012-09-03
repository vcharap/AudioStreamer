//
//  JBDownload.m
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#define STREAM_RETRY_COUNT 6

#import "JBDownload.h"

NSString* const JBDownloadErrorDomain = @"JBDownloadErrorDomain";

NSString* const JBDownloadOptionsFileOffsetKey = @"JBOptionsFileOffsetKey";
NSString* const JBDownloadErrorNotification = @"JBDownloadErrorNotification";
NSString* const JBDownloadWriteSuccessfulNotification = @"JBDownloadWriteSuccesfulNotification";

NSString* const JBDownloadWriteSuccessfulBytesWrittenKey = @"BytesWrittenKey";
NSString* const JBDownloadErrorNotificationErrorTypeKey = @"ErrorTypeKey";
NSString* const JBDownloadErrorNotificationExceptionKey = @"ExceptionKey";

NSString* const JBDownloadError_Exception = @"ErrorExceptionType";



@interface JBDownload ()
@property (strong, nonatomic) NSURLRequest *request;
@property (strong, nonatomic) NSDictionary *options;
@property (strong, nonatomic) NSFileHandle *fileWriter;

@property (readwrite) JBDownload_State state;
@property (readwrite) JBDownload_Error error;
@property (readwrite) JBDownload_Error_Code code;
@property (strong, readwrite) NSDictionary* headers;

-(void)failWithErrorCode:(JBDownload_Error_Code)code;

-(BOOL)openReadStream;
-(void)closeStream;
-(void)handleReadFromStream:(CFReadStreamRef) aStream eventType:(CFStreamEventType)eventType;

-(void)postNotification:(NSNotification*)notification;
-(void)notificationFired:(NSNotification*)notification;

@end

void JBReadStreamCallBack
(
 CFReadStreamRef aStream,
 CFStreamEventType eventType,
 void* inClientInfo
 )
{
	JBDownload* downloader = (__bridge JBDownload *)inClientInfo;
	[downloader handleReadFromStream:aStream eventType:eventType];
}

@implementation JBDownload
@synthesize request = _request, options = _options, fileWriter = _fileWriter, state = _state, error = _error, code = _code, bytesWritten = _bytesWritten, headers = _headers;
@synthesize bytesRead = _bytesRead;

-(id)initWithURLRequest:(NSURLRequest *)request filePath:(NSString*)filePath options:(NSDictionary *)options 
{
    return [self initAsyncWithURLRequest:request filePath:filePath options:options writeQueue:dispatch_get_main_queue()];
}

-(id)initAsyncWithURLRequest:(NSURLRequest *)request filePath:(NSString *)filePath options:(NSDictionary *)options writeQueue:(dispatch_queue_t)writeQueue
{
    
    if(!filePath || !request) return nil;
    
    if( self = [super init]){
        _writeQueue = writeQueue;
        _request = request;
        _filePath = [filePath copy];
        _options = options;
        _state = JBDownload_State_INIT;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationFired:) name:JBDownloadErrorNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationFired:) name:JBDownloadWriteSuccessfulNotification object:nil];
    }
    return self;
}

-(void)dealloc
{    
    [self closeStream];
    [_fileWriter closeFile];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(BOOL)start
{
    if( !(_fileWriter = [NSFileHandle fileHandleForWritingAtPath:_filePath]) ){
        [self failWithErrorCode:JBDownload_FILE_MISSING];
        return NO;
    }
    
    _retryCount = STREAM_RETRY_COUNT;
    _bytesWritten = 0;
    _bytesRead = 0;
    
    NSNumber *offset = nil;
    if( (offset = [self.options objectForKey:JBDownloadOptionsFileOffsetKey]) ){
        [self.fileWriter seekToFileOffset:[offset unsignedLongLongValue]];
    }
    return [self openReadStream];
}

-(void)stop
{
    [self closeStream];
    if(self.state != JBDownload_State_ERROR){
       self.state = JBDownload_State_USER_STOP; 
    }
}

-(void)failWithErrorCode:(JBDownload_Error_Code)code
{
    if(!code) return;
    
    self.state = JBDownload_State_ERROR;
    self.code = code;
    if(code < 50){
        self.error = JBDownload_Error_NETWORK;
    }
    else if(code < 100){
        self.error = JBDownload_Error_STREAM;
    }
    else if(code < 150){
        self.error = JBDownload_Error_HTTP;
    }
    else if(code < 200){
    
    }
    else if(code < 250){
        self.error = JBDownload_Error_FILE;
    }
    
    [self closeStream];
}

-(void)closeStream
{
    if(_stream){
        CFReadStreamClose(_stream);
        CFRelease(_stream);
        _stream = nil;
    }
}

-(BOOL)openReadStream
{
		//
		// Create the HTTP GET request
		//
		CFHTTPMessageRef message= CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef)[self.request URL], kCFHTTPVersion1_1);
		
		//
		// If we are creating this request to seek to a location, set the
		// requested byte range in the headers.
		//
		if ([self.request valueForHTTPHeaderField:@"Range"])
		{
			CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"),
                                             (__bridge CFStringRef)[self.request valueForHTTPHeaderField:@"Range"]);
		}
		
		//
		// Create the read stream that will receive data from the HTTP request
		//
		_stream = CFReadStreamCreateForHTTPRequest(NULL, message);
		CFRelease(message);
		
		//
		// Enable stream redirection
		//
		if (CFReadStreamSetProperty(
                                    _stream,
                                    kCFStreamPropertyHTTPShouldAutoredirect,
                                    kCFBooleanTrue) == false)
		{
            self.error = JBDownload_Error_STREAM;
            self.code = JBDownload_STREAM_SETPROP_ERR;
			return NO;
		}
		
        
        /*
         //
         // Handle proxies
         //
         CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
         CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxySettings);
         CFRelease(proxySettings);
         */
        
        
		//
		// Handle SSL connections
		//
		if( [[[self.request URL] absoluteString] rangeOfString:@"https"].location != NSNotFound )
		{
			NSDictionary *sslSettings =
            [NSDictionary dictionaryWithObjectsAndKeys:
             (NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL, kCFStreamSSLLevel,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
             [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
             [NSNull null], kCFStreamSSLPeerName,
             nil];
            
			CFReadStreamSetProperty(_stream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)sslSettings);
		}
        
        
		//
		// We're now ready to receive data
		//
        
        
		//
		// Open the stream
		//
		if (!CFReadStreamOpen(_stream))
		{
			CFRelease(_stream);
            _stream = nil;
            self.error = JBDownload_Error_STREAM;
            self.code = JBDownload_STREAM_OPEN_ERR;
			return NO;
		}
		
		//
		// Set our callback function to receive the data
		//
		CFStreamClientContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
		CFReadStreamSetClient(
                              _stream,
                              kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered,
                              JBReadStreamCallBack,
                              &context);
		CFReadStreamScheduleWithRunLoop(_stream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
	
        //Register as observer of Async write callbacks

	
    self.state = JBDownload_State_STREAM_OPEN;
	return YES;

}

-(void)handleReadFromStream:(CFReadStreamRef)aStream eventType:(CFStreamEventType)eventType
{
    if(aStream != _stream){
        return;
    }
    
    if(eventType == kCFStreamEventErrorOccurred){
        //DLog(@"kCFStreamEventErrorOccurred");
        CFErrorRef errRef = CFReadStreamCopyError(aStream);
        CFIndex code = CFErrorGetCode(errRef);
        CFRelease(errRef);
        
        //reconnect if -1005 error
        if(code == -1005 && _retryCount){
            _retryCount--;
            
            [self closeStream];
            
            [self openReadStream];
            return;
        }
        
        //self.state = JBDownload_State_ERROR;
        if(code == -1005){
            [self failWithErrorCode:JBDownload_STREAM_RECONNECT_FAILED];
        }
        else if(code == -1009){
            [self failWithErrorCode:JBDownload_NETWORK_OFFLINE];
        }
        else{
            [self failWithErrorCode:JBDownload_STREAM_UNCLASSIFIED_ERROR];
        }
    }
    else if (eventType == kCFStreamEventEndEncountered){
        self.state = JBDownload_State_STREAM_EOF;
        [self closeStream];
    }
    else if (eventType == kCFStreamEventHasBytesAvailable){
        //NSLog(@"Stream Bytes Available");
        if(!self.headers){
            CFTypeRef message =
            CFReadStreamCopyProperty(_stream, kCFStreamPropertyHTTPResponseHeader);
            
            UInt32 httpRespCode = CFHTTPMessageGetResponseStatusCode((CFHTTPMessageRef)message);
            
            CFDictionaryRef httpHeaders = CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message);
            self.headers = (__bridge NSDictionary*)httpHeaders;
            CFRelease(httpHeaders);
            CFRelease(message);
            
            if(httpRespCode == 401){
                [self failWithErrorCode:JBDownload_HTTP_AUTH_FAILED];
                return;
            }
            else if(httpRespCode == 404 || httpRespCode == 410){
                [self failWithErrorCode:JBDownload_HTTP_NOT_FOUND];
                return;
            }
            else if(httpRespCode >= 400 && httpRespCode <500){
                [self failWithErrorCode:JBDownload_HTTP_4xx_ERROR];
                return;
            }
        }
        
        
        UInt8 buffer[1024];
        CFIndex read = CFReadStreamRead(_stream, buffer, 1024);
        if(read > 0){
            
            _bytesRead += read;
            
            // Write data to file asynchronously in dispatch queue
            //
            NSData *bufferData = [NSData dataWithBytes:(const void*)buffer length:read];
            NSThread *objThread = [NSThread currentThread];
            
            dispatch_async(_writeQueue, ^{
                
                // Checking error state is not thread safe (eg could be in failWithError method when this block runs)
                // But that's OK, this check is here to prevent SOME number of reads after an error, but not necessarily ALL reads after an error
                //
                if(self.state == JBDownload_State_ERROR) return;
                
                NSNotification *notification;
                @try{
                    [_fileWriter writeData:bufferData];
                    
                    // Inform JBDownloader obj of succesful write, pass bytes written
                    //
                    notification = [NSNotification notificationWithName:JBDownloadWriteSuccessfulNotification 
                                                                 object:self
                                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:(NSInteger)read], JBDownloadWriteSuccessfulBytesWrittenKey, nil]];
                }
                @catch (NSException *exception) {
                    
                    // Inform JBDownloader of unsuccesful write, pass exception
                    //
                    notification = [NSNotification notificationWithName:JBDownloadErrorNotification 
                                                                 object:self 
                                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:JBDownloadError_Exception, JBDownloadErrorNotificationErrorTypeKey, exception, JBDownloadErrorNotificationExceptionKey, nil]];

                };
                [self performSelector:@selector(postNotification:) 
                             onThread:objThread 
                           withObject:notification 
                        waitUntilDone:NO];
                
            });
        }
        else if(read == 0){
            self.state = JBDownload_State_STREAM_EOF;
            [self closeStream];
        }
        else if(read == -1){
            [self failWithErrorCode:JBDownload_STREAM_UNCLASSIFIED_ERROR];
        } 
        
    }
}

-(void)postNotification:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}


-(void)notificationFired:(NSNotification *)notification
{
    if(self.state != JBDownload_State_ERROR && [[notification name] isEqualToString:JBDownloadErrorNotification]){
    
        if([[[notification userInfo] objectForKey:JBDownloadErrorNotificationErrorTypeKey] isEqualToString:JBDownloadError_Exception] ){
            //NSException *exception = [[notification userInfo] objectForKey:JBDownloadErrorNotificationExceptionKey];
            [self failWithErrorCode:JBDownload_WRITE_EXCEPTION];
        }
    }
    else if ([[notification name] isEqualToString:JBDownloadWriteSuccessfulNotification]){
        _bytesWritten += [[[notification userInfo] objectForKey:JBDownloadWriteSuccessfulBytesWrittenKey] integerValue];
        NSLog(@"Wrote %d bytes", _bytesWritten);
    }
}
@end
