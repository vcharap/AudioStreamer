//
//  JBSongFetcher.m
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "JBSongFetcher.h"
#import "NSString+NSString_MD5.h"
#import "NSArray+NSArray_FirstObject.h"

NSString* const JBSongFetcherErrorDomain = @"JBSongFetcherErrDomain";
NSString* const JBSongFetcherInfoDataKey = @"JBSongFetcherInfoDataKey";
NSString* const JBSongFetcherErrorKey = @"JBSongFetcherErrorKey";

static NSString* const JBSongFetcherReadInfoDataKey = @"JBSongfetcherReadInfoDataKey";
static NSString* const JBSongFetcherReadInfoErrorKey = @"JBSongFetcherReadInfoErrorKey";

static NSString* const JBSongFetcherReadExceptionKey = @"JBSongFetcherExceptionKey";

@interface JBSongFetcher ()

@property (readonly) NSFileHandle* consumer;
@property (readonly) NSString* filePath;
@property (readonly) NSString* libraryDirPath;
@property (readwrite) JBSongFetcherState state;
@property (readwrite) JBSongFetcherError error;

-(void)queueWriteNotification;
-(void)queuePauseNotification;
-(void)readDataWithInfo:(NSDictionary*)info;
-(void)readTimerFired:(NSTimer*)timer;
-(void)invalidateTimer;
-(unsigned long long)fetchByteForRequested:(unsigned long long)byte;
-(void)failWithError:(JBSongFetcherError)err;

@end


@implementation JBSongFetcher


@synthesize fileLength = _fileLength, bytesAvailable = _bytesAvailable, state = _state, error = _error;
@synthesize libraryDirPath = _libraryDirPath, filePath = _filePath, consumer = _consumer;

-(NSString*)libraryDirPath
{
    if(!_libraryDirPath){
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        _libraryDirPath = [paths firstObject];
    }
    return _libraryDirPath;
}

-(NSString*)filePath
{
    if(!_filePath){
        _filePath = [self.libraryDirPath stringByAppendingPathComponent:[[_songURL path] MD5]];
    }
    return _filePath;
}

-(NSInteger)fileLength
{
    if(!_fileLength){
        _fileLength = [[_downloader.headers objectForKey:@"Content-Length"] integerValue];
    }
    return _fileLength;
}

-(id)initWithURL:(NSURL *)songURL andDelegate:(id<JBSongFetcherDelegate>)callbackDelegate
{
    if(!songURL || !callbackDelegate) return nil;
    
    if(self = [super init]){
        _songURL = songURL;
        _callbackDelegate = callbackDelegate;
        _fileLength = 0;
        _bytesAvailable = 0;
        _queue = dispatch_queue_create("ReadWriteQueue", NULL);
        _fetchByteSize = 2048*10;
        _readInterval = 0.1;
    }
    return self;
}

-(void)dealloc
{
    [self stop];
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
    NSLog(@"Did delete file? %d", deleted);
}

// Function stops the download of song data and the handing of data to delegate
// 
-(void)stop
{
    [self invalidateTimer];
    self.state = JBSongFetcherState_USER_STOPPED;
    [self stopDownloader];
    
    if(_consumer){
        [_consumer closeFile];
        _consumer = nil;
    }
    
}

-(void)stopDownloader
{
    if(_downloader){
        [_downloader stop];
        _downloader = nil;
    }
}

-(void)failWithError:(JBSongFetcherError)err
{
    [self invalidateTimer];
    self.state = JBSongFetcherState_ERROR;
    self.error = err;
    
    [self stopDownloader];
}

// Function pauses the handing over of data to delegate, but does not stop the download of data.
// Function has no effect if not in FETCHING or FLUSHING states. 
//
-(void)pause
{
    if(self.state == JBSongFetcherState_FETCHING){
        
        [self invalidateTimer];
        self.state = JBSongFetcherState_PAUSING;
        
        // Put a "delimeter" on the read/write queue to signify when all reads prior to pause have completed
        //
        NSThread *currentThread = [NSThread currentThread];
        dispatch_async(_queue, ^{
            [self performSelector:@selector(queuePauseNotification) onThread:currentThread withObject:nil waitUntilDone:NO];
        });
    }
    else if(self.state == JBSongFetcherState_FLUSHING){
        
        // Set state to pausing. No need to throw a callback onto the read/write queue
        // since there is already a flushing "delimiter" on the read/write queue and the reads
        // are not being handed over to delegate
        
        [self invalidateTimer];
        self.state = JBSongFetcherState_PAUSING;
    }
}

// Function resumes fetching if in PAUSED state.
//
-(void)unPause
{
    if(self.state == JBSongFetcherState_PAUSED){
        [self fetchDataFromByte:_fetchFromByte];
    }
}


-(void)fetchData
{
    [self fetchDataFromByte:0];
}

// 
//
//
-(void)fetchDataFromByte:(unsigned long long)byte
{    
    if(self.state == JBSongFetcherState_FETCHING){
        
        
        // If currently fetching there maybe be reads to be processed by queue.
        // Those reads should not hand data over to delegate, the data will be stale.
        //
        // Set state to FLUSHING and do not pass data to delegate until queueWriteNotification goes off - by then all stale reads would have executed
        //
        
        self.state = JBSongFetcherState_FLUSHING;
        [self invalidateTimer];
        
        //save requested byte
        _fetchFromByte = byte;

        NSThread *currentThread = [NSThread currentThread];
        dispatch_async(_queue, ^{
            [self performSelector:@selector(queueWriteNotification) onThread:currentThread withObject:nil waitUntilDone:NO]; 
        });
        
        [_callbackDelegate willStartFetching];
        
        /*
        [(NSObject*)_callbackDelegate performSelector:@selector(willStartFetching) onThread:currentThread withObject:nil waitUntilDone:NO];
        */
    }
    else if(self.state == JBSongFetcherState_INIT || self.state == JBSongFetcherState_FLUSHED || self.state == JBSongFetcherState_PAUSED){
        
        //create file on disk
        //
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.filePath]){
            BOOL success = [[NSFileManager defaultManager] createFileAtPath:self.filePath contents:nil attributes:nil];
            
            if(!success){
                [self failWithError:JBSongFetcherError_FILE_CREATE];
                [_callbackDelegate failedToFetchWithError:[NSError errorWithDomain:JBSongFetcherErrorDomain code:self.error userInfo:nil]];
                /*
                [(NSObject*)_callbackDelegate performSelector:@selector(failedToFetchWithError:) 
                                                     onThread:[NSThread currentThread] 
                                                   withObject:[NSError errorWithDomain:JBSongFetcherErrorDomain code:self.error userInfo:nil] waitUntilDone:NO];
                */
                return;
            }
        }
        
        // Create and start downloader
        //
        if(!_downloader){
            NSURLRequest *req = [NSURLRequest requestWithURL:_songURL];
            _downloader = [[JBDownload alloc] initAsyncWithURLRequest:req filePath:self.filePath options:nil writeQueue:_queue];
            
            if(![_downloader start]){
                [self failWithError:JBSongFetcherError_DOWNLOADER_ERR];
                [_callbackDelegate failedToFetchWithError:[NSError errorWithDomain:JBSongFetcherErrorDomain code:self.error userInfo:nil]];
                
                /*
                
                [(NSObject*)_callbackDelegate performSelector:@selector(failedToFetchWithError:) 
                                                     onThread:[NSThread currentThread] 
                                                   withObject:[NSError errorWithDomain:JBSongFetcherErrorDomain code:self.error userInfo:nil] 
                                                waitUntilDone:NO];
                */
                
                
                return;
            }
            
        }
        
        // create data consumer
        //
        if(!_consumer){
             _consumer = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
        }
        _fetchFromByte = [self fetchByteForRequested:byte];
        [_consumer seekToFileOffset:_fetchFromByte];
        
        
        //start timer
        //
        _readTimer = [NSTimer scheduledTimerWithTimeInterval:_readInterval target:self selector:@selector(readTimerFired:) userInfo:nil repeats:YES];
        
        
        self.state = JBSongFetcherState_FETCHING;
        
        [_callbackDelegate didStartFetchingFromByte:_fetchFromByte];
        
        /*
        [(NSObject*)_callbackDelegate performSelector:@selector(didStartFetchingFromByte:) 
                                             onThread:[NSThread currentThread] 
                                           withObject:[NSNumber numberWithLongLong:_fetchFromByte] waitUntilDone:NO];
        */ 
        
    }
    else{
        [_callbackDelegate failedToFetchWithError:[NSError errorWithDomain:JBSongFetcherErrorDomain code:JBSongFetcherError_FETCH_IGNORED userInfo:nil]];
        
        /*
        [(NSObject*)_callbackDelegate performSelector:@selector(failedToFetchWithError:) 
                                             onThread:[NSThread currentThread] 
                                           withObject:[NSError errorWithDomain:JBSongFetcherErrorDomain code:JBSongFetcherError_FETCH_IGNORED userInfo:nil] 
                                        waitUntilDone:NO];
        */
    }
}

// Function "normalizes" the requested fetch byte value to between 0 and size of the file on disk
//
-(unsigned long long)fetchByteForRequested:(unsigned long long)byte
{
    NSError *err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:&err];
    unsigned long long fileSize = [attrs fileSize];
    
    if(byte > fileSize){
        byte = fileSize;
    }
    return byte;
}

-(void)invalidateTimer
{
    if(_readTimer){
        [_readTimer invalidate];
        _readTimer = nil;
    }
}

#pragma mark Data callbacks

// Function is called from the read/write queue after a read operation
// 
// @args - info
//      Contains key JBSongFetcherReadInfoDataKey -> NSData value, the data read from file
//      If there was a read error contains JBSongFetcherReadInfoErrorKey -> NSError value, describing the read error
//
-(void)readDataWithInfo:(NSDictionary *)info
{
    // Stop fetching and inform delegate if read error
    //
    NSError *error = [info objectForKey:JBSongFetcherReadInfoErrorKey];
    if( error && self.state != JBSongFetcherState_ERROR ){
        [self invalidateTimer];
        self.state = JBSongFetcherState_ERROR;
        self.error = [error code];
        
        [_callbackDelegate handleEvent:JBSongFetcherEvent_ERROR 
                            forFetcher:self 
                              withInfo:[NSDictionary dictionaryWithObject:error forKey:JBSongFetcherErrorKey]];
        return;
    }
    
    NSData *data = [info objectForKey:JBSongFetcherReadInfoDataKey];
    
    
    if(self.state == JBSongFetcherState_FETCHING){
        
        if([data length]){
            NSLog(@"HANDING BYTES OVER");
                [_callbackDelegate handleEvent:JBSongFetcherEvent_BYTES_AVAILABLE 
                                    forFetcher:self 
                                      withInfo:[NSDictionary dictionaryWithObject:data forKey:JBSongFetcherInfoDataKey]];
        }
        else{
            if(_downloader.state == JBDownload_State_STREAM_EOF){
                [self invalidateTimer];
                self.state = JBSongFetcherState_EOF;
                [_callbackDelegate handleEvent:JBSongFetcherEvent_EOF forFetcher:self withInfo:nil];
            }
            else if(_downloader.state == JBDownload_State_ERROR){
                [self invalidateTimer];
                self.state = JBSongFetcherState_ERROR;
                self.error = JBSongFetcherError_DOWNLOADER_ERR;
                
                NSDictionary *info= [NSDictionary dictionaryWithObject:[NSError errorWithDomain:JBDownloadErrorDomain code:_downloader.code userInfo:nil] 
                                                   forKey:JBSongFetcherErrorKey];
                
                [_callbackDelegate handleEvent:JBSongFetcherEvent_ERROR forFetcher:self withInfo:info];
            }
        } 
    }
    else if(self.state == JBSongFetcherState_PAUSING){
        
        // Record how many bytes are being ingnored. Will rewind file pointer by this amount
        //
        _rewindBytes += [data length];
    }
}

// Function is the read timer's callback.
// Adds a read operation to the read/write queue if in FETCHING state, otherwise does nothing
//
-(void)readTimerFired:(NSTimer*)timer
{   
    if(self.state == JBSongFetcherState_FETCHING){
        NSThread *currentThread = [NSThread currentThread];
        
        dispatch_async(_queue, ^{
            
            NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
            @try{
                NSLog(@"READING BYTES");
                NSData *data = [_consumer readDataOfLength:_fetchByteSize];
                [info setValue:data forKey:JBSongFetcherReadInfoDataKey];
                NSLog(@"READ BYTES");
            }
            @catch (NSException* exception){
                NSError *err = [NSError errorWithDomain:JBSongFetcherErrorDomain 
                                                   code:(NSInteger)JBSongFetcherError_READ_EXCEPTION 
                                               userInfo:[NSDictionary dictionaryWithObject:exception forKey:JBSongFetcherReadExceptionKey]];
                
                [info setValue:err forKey:JBSongFetcherReadInfoErrorKey];
            }

            [self performSelector:@selector(readDataWithInfo:) 
                         onThread:currentThread 
                       withObject:[NSDictionary dictionaryWithDictionary:info] 
                    waitUntilDone:NO];
        });
    }
}

#pragma mark Notifications

/*
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(object == _downloader){
        if([keyPath isEqualToString:@"state"]){
            JBDownload_State state = _downloader.state;
            
            if(state == JBDownload_State_STREAM_EOF){
                
            }
            else if(state == JBDownload_State_ERROR){
                    
            }
        }
    }
}
*/

// Callback signifying all queued reads after a PAUSE request have been processed
// Function sets _fetchFromByte by subtrating how many read bytes have been "ignored" 
// after PAUSE was requested from the current location of the file pointer
//
-(void)queuePauseNotification
{
    if(self.state == JBSongFetcherState_PAUSING){
        self.state = JBSongFetcherState_PAUSED;
        
        _fetchFromByte = [_consumer offsetInFile] - _rewindBytes;
        _rewindBytes = 0;
    }
}
             

// Callback signifying that all queued reads after SEEK request have been processed
// Function starts fetch from requested seek byte, or enters PAUSED state
//
-(void)queueWriteNotification
{
    // state can be PAUSING if PAUSE request came in while in FLUSHING state
    // Since this notification signifies no more reads on the queue, we can enter PAUSED state
    //
    if(self.state == JBSongFetcherState_PAUSING){
        self.state = JBSongFetcherState_PAUSED;
        _rewindBytes = 0;
    }
    else if(self.state == JBSongFetcherState_FLUSHING){
        // Start fetching. _fetchFromByte was the value requested by the fetch
        //
        self.state = JBSongFetcherState_FLUSHED;
        [self fetchDataFromByte:_fetchFromByte];
    }
}

@end
