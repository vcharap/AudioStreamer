//
//  JBSongFetcher.h
//  AudioStreamerPersistence
//
//  Created by Victor Charapaev on 8/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JBDownload.h"


extern NSString* const JBSongFetcherErrorDomain;

// Keys for info dictionary passed in hadleEvent:forFetcher:withInfo 
//
extern NSString* const JBSongFetcherErrorKey;       // Key for NSError obj passed when JBSongFetcher fails
extern NSString* const JBSongFetcherInfoDataKey;    // Key for NSData obj passed on succesful read

typedef enum
{
    JBSongFetcherEvent_EOF = 100,
    JBSongFetcherEvent_ERROR,
    JBSongFetcherEvent_BYTES_AVAILABLE

} JBSongFetcherEventType;

typedef enum
{
    JBSongFetcherState_INIT = 0,
    JBSongFetcherState_FETCHING,
    JBSongFetcherState_FLUSHING,
    JBSongFetcherState_FLUSHED,
    JBSongFetcherState_PAUSING,
    JBSongFetcherState_PAUSED,
    JBSongFetcherState_USER_STOPPED,
    JBSongFetcherState_EOF,
    JBSongFetcherState_ERROR
    
} JBSongFetcherState;

typedef enum
{
    JBSongFetcherError_NONE,
    JBSongFetcherError_FETCH_IGNORED,
    JBSongFetcherError_FILE_CREATE = 100,
    JBSongFetcherError_DOWNLOADER_ERR = 200,
    JBSongFetcherError_READ_ERROR = 300,
    JBSongFetcherError_READ_EXCEPTION
    
} JBSongFetcherError;

@class JBSongFetcher;

@protocol JBSongFetcherDelegate <NSObject>

@required
-(void)handleEvent:(JBSongFetcherEventType)event forFetcher:(JBSongFetcher*)songFetcher withInfo:(NSDictionary*)info;
-(void)didStartFetchingFromByte:(unsigned long long)byte;
-(void)willStartFetching;
-(void)failedToFetchWithError:(NSError*)error;
-(void)didPause;

@end

@interface JBSongFetcher : NSObject
{
    JBSongFetcherState _state;
    JBSongFetcherError _error;
    BOOL _staleRead;
    
    NSURL *_songURL;
    __weak id  <JBSongFetcherDelegate> _callbackDelegate;
    
    JBDownload *_downloader;
    NSFileHandle *_consumer;
    NSTimer* _readTimer;
    NSTimeInterval _readInterval;
    dispatch_queue_t _queue;
    
    NSString* _libraryDirPath;
    NSString* _filePath;
    
    unsigned long long _fetchFromByte;
    NSInteger _fileLength;
    NSInteger _bytesAvailable;
    NSInteger _fetchByteSize;
    NSInteger _rewindBytes;
}

@property (readonly) NSInteger fileLength;
@property (readonly) NSInteger bytesAvailable;
@property (readonly) JBSongFetcherState state;
@property (readonly) JBSongFetcherError error;

-(id)initWithURL:(NSURL*)songURL andDelegate:(id <JBSongFetcherDelegate>)callbackDelegate;
-(void)fetchData;
-(void)fetchDataFromByte:(unsigned long long)byte;
-(void)stop;
-(void)pause;
-(void)unPause;
@end
