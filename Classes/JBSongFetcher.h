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

/*
 @ abstract    
            Function is called whenever SongFetcher has bytes available.
 
 @param
    event   
            The event associated with the callback.
 
 @param 
    songFetcher
            The object making the callback
 
 @param
    info
            A dictionary containing information about the callbacks
            Any data is passed through the JBSongFetcherInfoDataKey
            Any errors are passed through the JBSongFetcherErrorKey
    
*/ 
-(void)handleEvent:(JBSongFetcherEventType)event forFetcher:(JBSongFetcher*)songFetcher withInfo:(NSDictionary*)info;

/*
 @abstract
            Function informs from which byte subsequent callbacks will start
 
 @param
    byte
            The byte in the stream from which callbacks will begin
 
 */
-(void)didStartFetchingFromByte:(unsigned long long)byte;

/*
 @abstract
            Function confirms that a seek request is being processed. A didStartFetchingFromByte: will follow at some point
 */
-(void)willStartFetching;

/*
 @abstract
            Function informs of a fetch error that has occured before any fetching of bytes has been attempted.
 
 @discussion
            This function is called when there is an error within fetchDataFromByte: Some errors are fatal and put
            SongFetcher in an ERROR state. Other errors more like warnings, warning that a fetchData request has been ignored
            due because a fetchData would not be compatible with current state.
 
 @params
    error
            The reason for the failed fetch. Error domain can be JBSongFetcherErrorDomain or JBDownloadErrorDomain
 */
-(void)failedToFetchWithError:(NSError*)error;

/*
 @abstract
            Function informs of a succesful pause
 */
-(void)didPause;

@end

/*
 @object 
            JBSongFetcher
 @abstract
            The JBSongFetcher object facilitates audio file persistence by downloading a file to, and subsequently streaming from, the disk.
            A client of SongFetcher creates the object, registers as a delegate, and recieves "stream like"
            async callbacks whenever there is data available.
            The client can pause, stop and seek with the stream data, without having to refetch anything. 
 
 @description
            The SongFetcher object works in tandem with a JBDownload object to facilitate persistence.
            JBDownload is responsible for streaming the file from network and writing it to disk.
            JBSongFetcher then reads the file, and hands available data to its delegate. All Disk IO happens on a dispatch queue.
            All calls to JBSongFetcher must come from the same thread. Callbacks happen on that thread as well.
            The thread must have an active run loop in order for JBSongFetcher to function.
 */
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

/*
 @abstract
            Returns the total length of the file as given by Content-Length header
*/
@property (readonly) NSInteger fileLength;

/*
 @abstract
            Returns the currently available number of bytes.
 */
@property (readonly) NSInteger bytesAvailable;
@property (readonly) JBSongFetcherState state;
@property (readonly) JBSongFetcherError error;

-(id)initWithURL:(NSURL*)songURL andDelegate:(id <JBSongFetcherDelegate>)callbackDelegate;

/*
 @abstract 
            Function begins fetching from byte 0
 
*/
-(void)fetchData;

/*
 @abstract
            Function starts SongFetcher, from the requested byte
 @discussion
            If the call is succesful, the delegate will receive a didStartFetchingFromByte: callback
            If the call is unssuccseful, a failedToFetchWithError: callback is made. 
            The thread from which this call is made must have an active run loop.
 
 @params
    byte
            The byte from which to begin fetching. Note that the requested fetch byte and the actual fetch byte can differ if request is out of bounds.
            The delegate is informed of the actual fetch byte in the callback.
            
 */
-(void)fetchDataFromByte:(unsigned long long)byte;

/*
 @abstract
            Function stops the download of the song and all data callbacks. 
            It is possible to call fetchDataFormByte again after a stop
 */
-(void)stop;

/*
 @abstract
            Function stops data callbacks, but does not stop the download to disk. 
            Function has no effect if not in FETCHING or FLUSHING states. 
            On a succesful pause, a didPause callback will follow
 */
-(void)pause;

/*
 @abstract
            Function resumes data callbacks. SongFetcher must be in PAUSED state for function to have affect.
            If an unPause is succesful, a didStartFetchingFromByte: callback will follow, containg the byte from
            which the data is being fetched
            
 */
-(void)unPause;
@end
