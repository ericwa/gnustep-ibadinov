/* Implementation for NSURLConnection for GNUstep
   Copyright (C) 2006 Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: 2006
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */ 

#import "common.h"

#define	EXPOSE_NSURLConnection_IVARS	1
#import "Foundation/NSError.h"
#import "Foundation/NSRunLoop.h"
#import "GSURLPrivate.h"

@interface _NSURLConnectionDataCollector : NSObject {
    NSURLConnection	*_connection; /* not retained */
    NSMutableData   *_data;
    NSError         *_error;
    NSURLResponse   *_response;
    BOOL            _done;
}

- (BOOL)done;
- (NSData *)data;
- (NSError *)error;
- (NSURLResponse *)response;

- (NSURLConnection *)connection;
- (void)setConnection:(NSURLConnection *)aConnection;

@end


@implementation _NSURLConnectionDataCollector

- (id)init
{
    if (self = [super init])
    {
        _data = [NSMutableData new]; /* empty data unless we get an error */
    }
    return self;
}

- (void)dealloc
{
    [_data release];
    [_error release];
    [_response release];
    [super dealloc];
}

- (BOOL)done
{
    return _done;
}

- (NSData *)data
{
    return _data;
}

- (NSError *)error
{
    return _error;
}

- (NSURLResponse *)response
{
    return _response;
}

- (NSURLConnection *)connection
{
    return _connection;
}

- (void)setConnection:(NSURLConnection *)aConnection
{
    _connection = aConnection; /* not retained ... the connection retains us */
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    ASSIGN(_error, error);
    DESTROY(_data); /* on error, we make the data nil */
    _done = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    ASSIGN(_response, response);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    _done = YES;
}

@end


typedef struct
{
    NSMutableURLRequest   *_request;
    NSURLProtocol         *_protocol;
    id                    _delegate; /* retained */
    BOOL                  _debug;
} Internal;

#define	this ((Internal*)(self->_NSURLConnectionInternal))
#define	inst ((Internal*)(o->_NSURLConnectionInternal))


@implementation	NSURLConnection

+ (id)allocWithZone:(NSZone *)zone
{
    NSURLConnection	*connection = [super allocWithZone: zone];
    
    if (connection != nil)
    {
#if	GS_WITH_GC
        connection->_NSURLConnectionInternal = NSAllocateCollectable(sizeof(Internal), NSScannedOption);
#else
        connection->_NSURLConnectionInternal = NSZoneCalloc([self zone], 1, sizeof(Internal));
#endif
    }
    return connection;
}

+ (BOOL)canHandleRequest:(NSURLRequest *)request
{
    return [NSURLProtocol _classToHandleRequest:request] != nil;
}

+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    return AUTORELEASE([[self alloc] initWithRequest:request delegate:delegate]);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately
{
    /* If request is nil, Apple's implemenation will produce seg.fault. We should crash too, but may do it more gracefully. */
    if (!request)
    {
        [NSException raise:NSInvalidArgumentException format:@"Tried to init NSURLConnection with nil request"];
    }
    if (self = [super init])
    {
        this->_request = [request mutableCopyWithZone:[self zone]];
        this->_protocol = nil;
        /*
         * According to bug #35686, Cocoa has a bizarre deviation from the convention that delegates are not retained here.
         * For compatibility we retain the delegate and release it again when the operation is over.
         */
        this->_delegate = [delegate retain];
        this->_debug = GSDebugSet(@"NSURLConnection");
    }
    if (startImmediately) {
        [self start];
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    return [self initWithRequest:request delegate:delegate startImmediately:YES];
}

- (void)dealloc
{
    [self cancel];
    DESTROY(this->_request);
    NSZoneFree([self zone], this);
    _NSURLConnectionInternal = 0;
    [super dealloc];
}

- (void)start
{
    /* enrich the request with the appropriate HTTP cookies, if desired */
    if ([this->_request HTTPShouldHandleCookies] == YES)
    {
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[this->_request URL]];
        if ([cookies count] > 0)
        {
            NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
            NSEnumerator *enumerator = [headers keyEnumerator];
            
            NSString *header;
            while ((header = [enumerator nextObject]))
            {
                [this->_request addValue:[headers valueForKey:header] forHTTPHeaderField:header];
            }
        }
    }
    this->_protocol = [[NSURLProtocol alloc] initWithRequest:this->_request
                                              cachedResponse:nil
                                                      client:(id<NSURLProtocolClient>)self];
    [this->_protocol startLoading];
}

- (void)_stop
{
    [this->_protocol stopLoading];
    DESTROY(this->_protocol);
}

- (void)cancel
{
    [self _stop];
    DESTROY(this->_delegate);
}

- (void)finalize
{
    [self cancel];
}


@end


@implementation NSObject (NSURLConnectionDelegate)

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    return;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    return;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    return;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    return;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    return;
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return cachedResponse;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
    return request;
}

@end


@implementation NSURLConnection (NSURLConnectionSynchronousLoading)

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    NSData *data = nil;
    
    if (response)
    {
        *response = nil;
    }
    if (error)
    {
        *error = nil;
    }
    if ([self canHandleRequest: request] == YES)
    {
        _NSURLConnectionDataCollector *collector;
        NSURLConnection *connection;
        
        collector = [_NSURLConnectionDataCollector new];
        connection = [[self alloc] initWithRequest:request delegate:collector];
        if (connection)
        {
            NSRunLoop *loop;
            
            [collector setConnection:connection];
            loop = [NSRunLoop currentRunLoop];
            while ([collector done] == NO)
            {
                NSDate *limit;
                
                limit = [[NSDate alloc] initWithTimeIntervalSinceNow:1.0];
                [loop runMode:NSDefaultRunLoopMode beforeDate:limit];
                RELEASE(limit);
            }
            data = [[[collector data] retain] autorelease];
            if (response)
            {
                *response = [[[collector response] retain] autorelease];
            }
            if (error)
            {
                *error = [[[collector error] retain] autorelease];
            }
        }
        [connection release];
        [collector release];
    }
    return data;
}

@end


@implementation	NSURLConnection (URLProtocolClient)

- (void)URLProtocol:(NSURLProtocol *)protocol cachedResponseIsValid:(NSCachedURLResponse *)cachedResponse
{
    return;
}

- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error
{
    [this->_delegate connection: self didFailWithError: error];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data
{
    [this->_delegate connection:self didReceiveData:data];
}

- (void)URLProtocol: (NSURLProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [this->_delegate connection:self didReceiveAuthenticationChallenge:challenge];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy
{
    [this->_delegate connection:self didReceiveResponse:response];
    if (policy == NSURLCacheStorageAllowed || policy == NSURLCacheStorageAllowedInMemoryOnly)
    {
        /* FIXME ... cache response here? */
    }
}

#if __has_feature(objc_arc)
#  define RETAIN_AUTORELEASE(object) __strong id __strong_##object = object;
#else
#  define RETAIN_AUTORELEASE(object) [[self retain] autorelease];
#endif

- (void)URLProtocol:(NSURLProtocol *)protocol wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    RETAIN_AUTORELEASE(self);
    
    if (this->_debug)
    {
        NSLog(@"%@ tell delegate %@ about redirect to %@ as a result of %@", self, this->_delegate, request, redirectResponse);
    }
    request = [this->_delegate connection:self willSendRequest:request redirectResponse:redirectResponse];
    if (this->_protocol != nil)
    {
        if (request != nil)
        {
            if (this->_debug)
            {
                NSLog(@"%@ delegate allowed redirect to %@", self, request);
            }
            /* follow the redirect ... stop the old load and start a new one */
            [self _stop];
            ASSIGNCOPY(this->_request, request);
            [self start];
        }
        else if (this->_debug)
        {
            NSLog(@"%@ delegate cancelled redirect", self);
        }
    }
    else
    {
        /* our protocol is nil, so we have been cancelled by the delegate */
        if (this->_debug)
        {
            NSLog(@"%@ delegate cancelled request", self);
        }
    }
}

- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol
{
    [this->_delegate connectionDidFinishLoading:self];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [this->_delegate connection:self didCancelAuthenticationChallenge:challenge];
}

@end