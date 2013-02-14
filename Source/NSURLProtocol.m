/* Implementation for NSURLProtocol for GNUstep
   Copyright (C) 2006 Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: 2006
   Parts (FTP and About in particular) based on later code by Nikolaus Schaller
   
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

#define	EXPOSE_NSURLProtocol_IVARS	1
#import "Foundation/NSBundle.h"
#import "Foundation/NSError.h"
#import "Foundation/NSHost.h"
#import "Foundation/NSNotification.h"
#import "Foundation/NSRunLoop.h"
#import "Foundation/NSValue.h"

#import "GSPrivate.h"
#import "GSTLS.h"
#import "GSURLPrivate.h"
#import "GNUstepBase/GSMime.h"
#import "GNUstepBase/NSObject+GNUstepBase.h"
#import "GNUstepBase/NSString+GNUstepBase.h"
#import "GNUstepBase/NSURL+GNUstepBase.h"

/* Define to 1 for experimental (net yet working) compression support
 */
#ifdef	USE_ZLIB
# undef	USE_ZLIB
#endif
#define	USE_ZLIB	0

#if	USE_ZLIB
#if	defined(HAVE_ZLIB_H)
#include	<zlib.h>

static void*
zalloc(void *opaque, unsigned nitems, unsigned size)
{
  return calloc(nitems, size);
}
static void
zfree(void *opaque, void *mem)
{
  free(mem);
}
#else
# undef	USE_ZLIB
# define	USE_ZLIB	0
#endif
#endif

@interface	GSSocketStreamPair : NSObject
{
  NSInputStream		*ip;
  NSOutputStream	*op;
  NSHost		*host;
  uint16_t		port;
  NSDate		*expires;
  BOOL			ssl;
}
+ (void) purge: (NSNotification*)n;
- (void) cache: (NSDate*)when;
- (void) close;
- (NSDate*) expires;
- (id) initWithHost: (NSHost*)h port: (uint16_t)p forSSL: (BOOL)s;
- (NSInputStream*) inputStream;
- (NSOutputStream*) outputStream;
@end

@implementation	GSSocketStreamPair

static NSMutableArray	*pairCache = nil;
static NSLock		*pairLock = nil;

+ (void) initialize
{
  if (pairCache == nil)
    {
      /* No use trying to use a dictionary ... NSHost objects all hash
       * to the same value.
       */
      pairCache = [NSMutableArray new];
      pairLock = [NSLock new];
      /*  Purge expired pairs at intervals.
       */
      [[NSNotificationCenter defaultCenter] addObserver: self
	selector: @selector(purge:)
	name: @"GSHousekeeping" object: nil];
    }
}

+ (void) purge: (NSNotification*)n
{
  NSDate	*now = [NSDate date];
  NSUInteger	count;

  [pairLock lock];
  count = [pairCache count];
  while (count-- > 0)
    {
      GSSocketStreamPair	*p = [pairCache objectAtIndex: count];

      if ([[p expires] timeIntervalSinceDate: now] <= 0.0)
	{
	  [pairCache removeObjectAtIndex: count];
	}
    }
  [pairLock unlock];
}

- (void) cache: (NSDate*)when
{
  NSTimeInterval	ti = [when timeIntervalSinceNow];

  if (ti <= 0.0)
    {
      [self close];
      return;
    }
  NSAssert(ip != nil, NSGenericException);
  if (ti > 120.0)
    {
      ASSIGN(expires, [NSDate dateWithTimeIntervalSinceNow: 120.0]);
    }
  else
    { 
      ASSIGN(expires, when);
    }
  [pairLock lock];
  [pairCache addObject: self];
  [pairLock unlock];
}

- (void) close
{
  [ip setDelegate: nil];
  [op setDelegate: nil];
  [ip removeFromRunLoop: [NSRunLoop currentRunLoop]
		forMode: NSDefaultRunLoopMode];
  [op removeFromRunLoop: [NSRunLoop currentRunLoop]
		forMode: NSDefaultRunLoopMode];
  [ip close];
  [op close];
  DESTROY(ip);
  DESTROY(op);
}

- (void) dealloc
{
  [self close];
  DESTROY(host);
  DESTROY(expires);
  [super dealloc];
}

- (NSDate*) expires
{
  return expires;
}

- (id) init
{
  DESTROY(self);
  return nil;
}

- (id) initWithHost: (NSHost*)h port: (uint16_t)p forSSL: (BOOL)s;
{
  NSUInteger		count;
  NSDate		*now;

  now = [NSDate date];
  [pairLock lock];
  count = [pairCache count];
  while (count-- > 0)
    {
      GSSocketStreamPair	*pair = [pairCache objectAtIndex: count];

      if ([pair->expires timeIntervalSinceDate: now] <= 0.0)
	{
	  [pairCache removeObjectAtIndex: count];
	}
      else if (pair->port == p && pair->ssl == s && [pair->host isEqual: h])
	{
	  /* Found a match ... remove from cache and return as self.
	   */
	  DESTROY(self);
	  self = [pair retain];
	  [pairCache removeObjectAtIndex: count];
	  [pairLock unlock];
	  return self;
	}
    }
  [pairLock unlock];

  if ((self = [super init]) != nil)
    {
      [NSStream getStreamsToHost: host
			    port: port
		     inputStream: &ip
		    outputStream: &op];
      if (ip == nil || op == nil)
	{
	  DESTROY(self);
	  return nil;
	}
      ssl = s;
      port = p;
      host = [h retain];
      [ip retain];
      [op retain];
      if (ssl == YES)
        {
          [ip setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
		   forKey: NSStreamSocketSecurityLevelKey];
          [op setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
		   forKey: NSStreamSocketSecurityLevelKey];
        }
    }
  return self;
}

- (NSInputStream*) inputStream
{
  return ip;
}

- (NSOutputStream*) outputStream
{
  return op;
}

@end

@interface _NSAboutURLProtocol : NSURLProtocol
@end

@interface _NSFTPURLProtocol : NSURLProtocol
@end

@interface _NSFileURLProtocol : NSURLProtocol
@end

enum {
    NSHTTPURLProtocolStateStopped = 0,
    NSHTTPURLProtocolStateStarted,
    NSHTTPURLProtocolStateHasHeaders,
    NSHTTPURLProtocolStateFormedResponse,
    NSHTTPURLProtocolStateAwaitsHandshake,
    NSHTTPURLProtocolStateReceivedChallenge,
    NSHTTPURLProtocolStateRepliesToChallenge,
    NSHTTPURLProtocolStateReceivesContent,
    NSHTTPURLProtocolStateFinished
};
typedef uint8_t NSHTTPURLProtocolState;

@interface _NSHTTPURLProtocol : NSURLProtocol<NSURLAuthenticationChallengeSender>
{
    GSMimeParser    *_parser;       // Parser handling incoming data
    NSUInteger      _parseOffset;	// Bytes of body loaded in parser.
    float           _version;       // The HTTP version in use.
    int             _statusCode;	// The HTTP status code returned.
    NSInputStream   *_body;         // for sending the body
    NSUInteger		_writeOffset;	// Request data to write
    NSData          *_writeData;	// Request bytes written so far
    BOOL            _eof;
    BOOL            _debug;
    BOOL            _shouldClose;
    NSHTTPURLProtocolState          _state;
    NSURLAuthenticationChallenge    *_challenge;
    NSURLCredential                 *_credential;
    NSHTTPURLResponse               *_response;
}

- (void)setDebug:(BOOL)flag;

@end

@interface _NSHTTPURLProtocol (Private)

- (void)_processNewData;
- (BOOL)_processHeadersAndCreateReditrectedRequest:(NSURLRequest **)aRequest error:(NSError **)error;
- (NSURLAuthenticationChallenge *)_handleAuthenticationChallenge;
- (BOOL)_fulfillAuthenticationRequest:(NSURLRequest **)request error:(NSError **)error;
- (NSData *)_handleBody;
- (void)_handleFinish;

@end


@interface _NSHTTPSURLProtocol : _NSHTTPURLProtocol
@end


// Internal data storage
typedef struct {
  NSInputStream			*input;
  NSOutputStream		*output;
  NSCachedURLResponse		*cachedResponse;
  id <NSURLProtocolClient>	client;		// Not retained
  NSURLRequest			*request;
#if	USE_ZLIB
  z_stream			z;		// context for decompress
  BOOL				compressing;	// are we compressing?
  BOOL				decompressing;	// are we decompressing?
  NSData			*compressed;	// only partially decompressed
#endif
} Internal;
 
#define	this	((Internal*)(self->_NSURLProtocolInternal))
#define	inst	((Internal*)(o->_NSURLProtocolInternal))

static NSMutableArray	*registered = nil;
static NSLock		*regLock = nil;
static Class		abstractClass = nil;
static Class		placeholderClass = nil;
static NSURLProtocol	*placeholder = nil;

@interface	NSURLProtocolPlaceholder : NSURLProtocol
@end
@implementation	NSURLProtocolPlaceholder
- (void) dealloc
{
  if (self == placeholder)
    {
      [self retain];
      return;
    }
  [super dealloc];
}
- (oneway void) release
{
  /* In a multi-threaded environment we could have two threads release the
   * class at the same time ... causing -dealloc to be called twice at the
   * same time, so that we can get an exception as we try to decrement the
   * retain count beyond zero.  To avoid this we make the placeholder be a
   * subclass whose -retain method prevents us even calling -dealoc in any
   * normal circumstances.
   */
  return;
}
@end

@implementation	NSURLProtocol

+ (id) allocWithZone: (NSZone*)z
{
    NSURLProtocol	*o;
    
    if ((self == abstractClass) && (z == 0 || z == NSDefaultMallocZone()))
    {
        /* return a default placeholder instance to avoid the overhead of creating and destroying instances of the abstract class */
        o = placeholder;
    }
    else
    {
        /* Create and return an instance of the concrete subclass */
        o = (NSURLProtocol*)NSAllocateObject(self, 0, z);
    }
    return o;
}

+ (void) initialize
{
    if (registered == nil)
    {
        abstractClass = [NSURLProtocol class];
        placeholderClass = [NSURLProtocolPlaceholder class];
        placeholder = (NSURLProtocol*)NSAllocateObject(placeholderClass, 0,
                                                       NSDefaultMallocZone());
        registered = [NSMutableArray new];
        regLock = [NSLock new];
        [self registerClass: [_NSHTTPURLProtocol class]];
        [self registerClass: [_NSHTTPSURLProtocol class]];
        [self registerClass: [_NSFTPURLProtocol class]];
        [self registerClass: [_NSFileURLProtocol class]];
        [self registerClass: [_NSAboutURLProtocol class]];
    }
}

+ (id) propertyForKey: (NSString *)key inRequest: (NSURLRequest *)request
{
    return [request _propertyForKey: key];
}

+ (BOOL) registerClass: (Class)protocolClass
{
    if ([protocolClass isSubclassOfClass: [NSURLProtocol class]] == YES)
    {
        [regLock lock];
        [registered addObject: protocolClass];
        [regLock unlock];
        return YES;
    }
    return NO;
}

+ (Class) _classToHandleRequest:(NSURLRequest *)request
{
    Class protoClass = nil;
    NSInteger count;
    [regLock lock];
    
    count = [registered count];
    while (count-- > 0)
    {
        Class	proto = [registered objectAtIndex: count];
        
        if ([proto canInitWithRequest: request] == YES)
        {
            protoClass = proto;
            break;
        }
    }
    [regLock unlock];
    return protoClass;
}


+ (void) setProperty: (id)value
              forKey: (NSString *)key
           inRequest: (NSMutableURLRequest *)request
{
    [request _setProperty: value forKey: key];
}

+ (void) unregisterClass: (Class)protocolClass
{
    [regLock lock];
    [registered removeObjectIdenticalTo: protocolClass];
    [regLock unlock];
}

- (NSCachedURLResponse *) cachedResponse
{
    return this->cachedResponse;
}

- (id <NSURLProtocolClient>) client
{
    return this->client;
}

- (void) dealloc
{
    if (this != 0)
    {
        [self stopLoading];
        
        DESTROY(this->cachedResponse);
        DESTROY(this->request);
#if	USE_ZLIB
        if (this->compressing == YES)
        {
            deflateEnd(&this->z);
        }
        else if (this->decompressing == YES)
        {
            inflateEnd(&this->z);
        }
        DESTROY(this->compressed);
#endif
        NSZoneFree([self zone], this);
        _NSURLProtocolInternal = 0;
    }
    [super dealloc];
}

- (NSString*) description
{
    return [NSString stringWithFormat:@"%@ %@",
            [super description], this ? (id)this->request : nil];
}

- (id) init
{
    if ((self = [super init]) != nil)
    {
        Class	c = object_getClass(self);
        
        if (c != abstractClass && c != placeholderClass)
        {
            _NSURLProtocolInternal = NSZoneCalloc([self zone],
                                                  1, sizeof(Internal));
        }
    }
    return self;
}

- (id) initWithRequest: (NSURLRequest *)request
        cachedResponse: (NSCachedURLResponse *)cachedResponse
                client: (id <NSURLProtocolClient>)client
{
    Class	c = object_getClass(self);
    
    if (c == abstractClass || c == placeholderClass)
    {
        NSUInteger	count;
        
        DESTROY(self);
        [regLock lock];
        count = [registered count];
        while (count-- > 0)
        {
            Class	proto = [registered objectAtIndex: count];
            
            if ([proto canInitWithRequest: request] == YES)
            {
                self = [proto alloc];
                break;
            }
        }
        [regLock unlock];
        return [self initWithRequest: request
                      cachedResponse: cachedResponse
                              client: client];
    }
    if ((self = [self init]) != nil)
    {
        this->request = [request copy];
        this->cachedResponse = RETAIN(cachedResponse);
        this->client = client;	// Not retained
    }
    return self;
}

- (NSURLRequest *) request
{
    return this->request;
}

/* This method is here so that it's safe to set debug on any NSURLProtocol
 * even if the concrete subclass doesn't actually support debug logging.
 */
- (void) setDebug: (BOOL)flag
{
    return;
}

@end


@implementation	NSURLProtocol (Subclassing)

+ (BOOL) canInitWithRequest: (NSURLRequest *)request
{
  [self subclassResponsibility: _cmd];
  return NO;
}

+ (NSURLRequest *) canonicalRequestForRequest: (NSURLRequest *)request
{
  return request;
}

+ (BOOL) requestIsCacheEquivalent: (NSURLRequest *)a
			toRequest: (NSURLRequest *)b
{
  a = [self canonicalRequestForRequest: a];
  b = [self canonicalRequestForRequest: b];
  return [a isEqual: b];
}

- (void) startLoading
{
  [self subclassResponsibility: _cmd];
}

- (void) stopLoading
{
  [self subclassResponsibility: _cmd];
}

@end




@implementation _NSHTTPURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return [[[request URL] scheme] isEqualToString:@"http"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (id)init
{
    if (self = [super init])
    {
        _parser = nil;
        _body = nil;
        _writeData = nil;
        _challenge = nil;
        _credential = nil;
        _response = nil;
        _state = NSHTTPURLProtocolStateStopped;
        _debug = GSDebugSet(@"NSURLProtocol");
    }
    return self;
}

- (void)dealloc
{
    [_parser release];  /* received headers */
    [_body release];    /* for sending the body */
    [_writeData release];
    [_challenge release];
    [_credential release];
    [_response release];
    [super dealloc];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    if (c == _challenge)
    {
        DESTROY(_challenge); /* We should cancel the download */
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)c
{
    if (c == _challenge)
    {
        DESTROY(_credential); /* We download the challenge page */
    }
}

- (void)setDebug:(BOOL)flag
{
    _debug = flag;
}

- (NSURLRequestCachePolicy)_resolveCachePolicy
{
    NSURLRequestCachePolicy policy = [this->request cachePolicy];
    if (policy == (NSURLCacheStoragePolicy)NSURLRequestUseProtocolCachePolicy)
    {
        if ([self isKindOfClass: [_NSHTTPSURLProtocol class]])
        {
            /* For HTTPS we should not allow caching unless the request explicitly wants it */
            policy = NSURLCacheStorageNotAllowed;
        }
        else
        {
            /* For HTTP we allow caching unless the request specifically denies it */
            policy = NSURLCacheStorageAllowed;
        }
    }
    return policy;
}

NS_INLINE void
PostponeSelector(id self, SEL _cmd, id argument)
{
    [[NSRunLoop currentRunLoop] performSelector:_cmd target:self argument:argument order:0 modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
}

- (void)_wasRedirectedToRequest:(NSURLRequest *)aRequest
{
    PostponeSelector(self, @selector(_processNewData), nil);
    [this->client URLProtocol:self wasRedirectedToRequest:aRequest redirectResponse:_response];
}

- (void)_didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)aChallenge
{
    PostponeSelector(self, @selector(_processNewData), nil);
    [this->client URLProtocol:self didReceiveAuthenticationChallenge:aChallenge];
}

- (void)_didReceiveResponse
{
    PostponeSelector(self, @selector(_processNewData), nil);
    [this->client URLProtocol:self didReceiveResponse:_response cacheStoragePolicy:(NSURLCacheStoragePolicy)[self _resolveCachePolicy]];
}

- (void)_didLoadData:(NSData *)data
{
    PostponeSelector(self, @selector(_processNewData), nil);
    [this->client URLProtocol:self didLoadData:data];
}

- (void)_didFinishLoading
{
    [this->client URLProtocolDidFinishLoading:self];
}

- (void)_didFailWithError:(NSError *)anError
{
    NSURL *url = [this->request URL];
    NSString *urlString = [url absoluteString];
    NSMutableDictionary *userInfo = [[anError userInfo] mutableCopy];
    
    [userInfo setObject:url forKey:NSURLErrorKey];
    [userInfo setObject:url forKey:@"NSURLErrorFailingURLErrorKey"]; /* deprecated in Mac' Foundation */
    [userInfo setObject:urlString forKey:NSErrorFailingURLStringKey];
    [userInfo setObject:urlString forKey:@"NSURLErrorFailingURLStringErrorKey"]; /* deprecated in Mac' Foundation */
    
    NSError *error = [NSError errorWithDomain:[anError domain] code:[anError code] userInfo:userInfo];
    [userInfo release];
    
    [self stopLoading];
    [this->client URLProtocol:self didFailWithError:error];
}

- (NSError *)_errorWithCode:(NSInteger)aCode description:(NSString *)aDescription
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(aDescription, @"") forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:NSURLErrorDomain code:aCode userInfo:userInfo];
}

- (void)_didFailWithErrorDescription:(NSString *)aDescription code:(NSInteger)aCode
{
    [self _didFailWithError:[self _errorWithCode:aCode description:aDescription]];
}

- (void)_didFailWithErrorDescription:(NSString *)aDescription
{
    [self _didFailWithErrorDescription:aDescription code:NSURLErrorUnknown];
}

- (void)startLoading
{
    static NSDictionary *methods = nil;
    
    if (methods == nil)
    {
        methods = [[NSDictionary alloc] initWithObjectsAndKeys: 
                   self, @"HEAD",
                   self, @"GET",
                   self, @"POST",
                   self, @"PUT",
                   self, @"DELETE",
                   self, @"TRACE",
                   self, @"OPTIONS",
                   self, @"CONNECT",
                   nil];
    }
    if ([methods objectForKey:[this->request HTTPMethod]] == nil)
    {
        NSLog(@"Invalid HTTP Method: %@", this->request);
        [self _didFailWithErrorDescription:@"Invalid HTTP Method"];
        return;
    }
    if (_state != NSHTTPURLProtocolStateStopped)
    {
        NSLog(@"-[NSURLProtocol startLoading] can not be called while load is in progress");
        return;
    }
    
    _statusCode = 0;	/* No status returned yet.	*/
    _eof = NO;
    _state = NSHTTPURLProtocolStateStarted;
    _response = nil;
    
    if (0 && this->cachedResponse)
    {
        /* todo: handle cachedResponse */
    }

    NSURL *url = [this->request URL];
    NSHost *host = [NSHost hostWithName:[url host]];
    int	port = [[url port] intValue];
    
    _parseOffset = 0;
    DESTROY(_parser);
    
    if (host == nil)
    {
        host = [NSHost hostWithAddress:[url host]];	/* try dotted notation */
    }
    if (host == nil)
    {
        host = [NSHost hostWithAddress:@"127.0.0.1"]; /* final default */
    }
    if (port == 0)
    {
        /* default if not specified */
        port = [[url scheme] isEqualToString:@"https"] ? 443 : 80;
    }
    
    /* todo: support keep-alive, check if we already have a connection to this host */
    
    [NSStream getStreamsToHost:host
                          port:port
                   inputStream:&this->input
                  outputStream:&this->output];
    if (!this->input || !this->output)
    {
        if (_debug == YES)
        {
            NSLog(@"%@ did not create streams for %@:%@", self, host, [url port]);
        }
        [self _didFailWithErrorDescription:@"Can not find host" code:NSURLErrorCannotFindHost]; /* todo: specify host in error description */
        return;
    }
#if	!GS_WITH_GC
    [this->input retain];
    [this->output retain];
#endif
    if ([[url scheme] isEqualToString: @"https"] == YES)
    {
        static NSArray *keys;
        NSUInteger count;
        
        [this->input setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        [this->output setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        if (nil == keys)
        {
            keys = [[NSArray alloc] initWithObjects:
                    GSTLSCAFile,
                    GSTLSCertificateFile,
                    GSTLSCertificateKeyFile,
                    GSTLSCertificateKeyPassword,
                    GSTLSDebug,
                    GSTLSPriority,
                    GSTLSRemoteHosts,
                    GSTLSRevokeFile,
                    GSTLSVerify,
                    nil];
        }
        count = [keys count];
        while (count-- > 0)
        {
            NSString *key = [keys objectAtIndex:count];
            NSString *str = [this->request _propertyForKey:key];
            
            if (nil != str)
            {
                [this->output setProperty:str forKey:key];
            }
        }
        if (_debug) {
            [this->output setProperty:@"YES" forKey:GSTLSDebug];
        }
    }
    [this->input setDelegate:self];
    [this->output setDelegate:self];
    [this->input scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [this->output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [this->input open];
    [this->output open];
}

- (void)stopLoading
{    
    if (_debug == YES)
    {
        NSLog(@"%@ stopLoading", self);
    }
    
    [[NSRunLoop currentRunLoop] cancelPerformSelectorsWithTarget:self];
    _state = NSHTTPURLProtocolStateStopped;
    DESTROY(_writeData);
    
    /* todo: support keep-alive, check _shouldClose */
    
    [this->input setDelegate:nil];
    [this->output setDelegate:nil];
    [this->input removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [this->output removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [this->input close];
    [this->output close];
    DESTROY(this->input);
    DESTROY(this->output);
}

- (void)_got:(NSStream *)stream
{
    uint8_t buffer[BUFSIZ * 64];
    NSInteger readCount = [(NSInputStream *)stream read:buffer maxLength:sizeof(buffer)];
    if (readCount < 0)
    {
        if ([stream streamStatus] == NSStreamStatusError)
        {
            NSError *error = [stream streamError];
            if (_debug)
            {
                NSLog(@"%@ receive error %@", self, error);
            }
            [self _didFailWithError:error];
        }
        return;
    }
    if (_debug)
    {
        NSLog(@"%@ read %ld bytes: '%*.*s'", self, (long)readCount, (int)readCount, (int)readCount, buffer);
    }
    
    if (_parser == nil)
    {
        _parser = [GSMimeParser new];
        [_parser setIsHttp];
    }
    
    NSData *data = [NSData dataWithBytes:buffer length:readCount];
    if ([_parser parse:data] == NO && [_parser isComplete] == NO)
    {
        if (_debug == YES)
        {
            NSLog(@"%@ HTTP parse failure - %@", self, _parser);
        }
        [self _didFailWithErrorDescription:@"Parse error" code:NSURLErrorBadServerResponse];
        return;
    }
    
    _eof = readCount == 0;
    if (_eof && ![_parser isComplete])
    {
        /* Premature EOF, the read failed ... dropped, but parsing is not complete */
        /* The request was sent, so we can't know whether it was lost in the network or the remote end received it and the response was lost */
        if (_debug == YES)
        {
            NSLog(@"%@ HTTP response not received - %@", self, _parser);
        }
        [self _didFailWithErrorDescription:@"Failed to receive data" code:NSURLErrorCannotLoadFromNetwork];
        return;
    }
    
    [self _processNewData];
}

/* 
 * NOTE:
 * this method returns immediately after calling any method of the client,
 * and reschedules itself via -[NSRunLoop performSelector:target:argument:order:modes:],
 * this is done to ensure that client can safely release protocol object while being called by it
 */
- (void)_processNewData
{
    /* check if the client cancelled URL loading */
    if (_state == NSHTTPURLProtocolStateStopped)
    {
        return;
    }
    NSError *error = nil;
    switch (_state) {
        case NSHTTPURLProtocolStateStarted:
        {
            if ([_parser isInHeaders])
            {
                break;
            }
            _state = NSHTTPURLProtocolStateHasHeaders;
        }
        case NSHTTPURLProtocolStateHasHeaders:
        {
            NSURLRequest *request = nil;
            if (![self _processHeadersAndCreateReditrectedRequest:&request error:&error]) {
                [self _didFailWithError:error];
                return;
            }
            _state = NSHTTPURLProtocolStateFormedResponse;
            /* this behavior matches Apple's implemenation: it does not honor 201 and 300 status codes, as opposed to behavior suggested by standard */
            if (request && (_statusCode == 301 || _statusCode == 302 || _statusCode == 303 || _statusCode == 305 || _statusCode == 307)) {
                [self _wasRedirectedToRequest:request];
                return;
            }
        }
        case NSHTTPURLProtocolStateFormedResponse:
        {
            if (_statusCode != 401) {
                if (_statusCode == 204 || _statusCode == 304) { /* 1xx? */
                    _state = NSHTTPURLProtocolStateFinished; /* no body expected */
                } else {
                    _state = NSHTTPURLProtocolStateReceivesContent;
                }
                [self _didReceiveResponse];
                return;
            }
            /* 401 Unauthorized */
            _state = NSHTTPURLProtocolStateAwaitsHandshake;
        }
        case NSHTTPURLProtocolStateAwaitsHandshake:
        {
            if (![_parser isComplete]) {
                break;
            }
            _state = NSHTTPURLProtocolStateReceivedChallenge;
        }
        case NSHTTPURLProtocolStateReceivedChallenge:
        {
            NSURLAuthenticationChallenge *challenge = [self _handleAuthenticationChallenge];
            _state = NSHTTPURLProtocolStateRepliesToChallenge;
            [self _didReceiveAuthenticationChallenge:challenge];
            return;
        }
        case NSHTTPURLProtocolStateRepliesToChallenge:
        {
            NSURLRequest *request = nil;
            if (![self _fulfillAuthenticationRequest:&request error:&error]) {
                [self _didFailWithError:error];
                return;
            }
            if (!request)
            {
                /* We have no authentication credentials so we treat this as a download of the challenge page */
                _state = NSHTTPURLProtocolStateReceivesContent;
                [self _didReceiveResponse];
                return;
            }
            /* handshake will continue with new request */
            [this->request release];
            this->request = [request retain];
            DESTROY(this->cachedResponse);
            [self stopLoading];
            [self startLoading];
            break;
        }
        case NSHTTPURLProtocolStateReceivesContent:
        {
            NSData *chunk = [self _handleBody];
            if ([_parser isComplete]) {
                _state = NSHTTPURLProtocolStateFinished;
            }
            if (chunk) {
                [self _didLoadData:chunk];
                return;
            }
            if (_state != NSHTTPURLProtocolStateFinished) {
                break;
            }
        }
        case NSHTTPURLProtocolStateFinished:
        {
            [self _handleFinish];
            _state = NSHTTPURLProtocolStateStopped;
            [self _didFinishLoading];
            return;
        }
        default:
        {
            [self _didFailWithErrorDescription:@"Unsupported HTTP protocol state"];
            break;
        }
    }
}

- (BOOL)_processHeadersAndCreateReditrectedRequest:(NSURLRequest **)aRequest error:(NSError **)error
{
    *aRequest = nil;
    GSMimeDocument *document = [_parser mimeDocument];
    GSMimeHeader *info;
    NSString    *enc;
    int         len = -1;
    NSString    *ct;
    NSString    *st;
    NSString    *s;
    
    info = [document headerNamed:@"http"];
    
    _version = [[info value] floatValue];
    if (_version < 1.1)
    {
        _shouldClose = YES;
    }
    else if ((s = [[document headerNamed:@"connection"] value]) != nil && [s caseInsensitiveCompare:@"close"] == NSOrderedSame)
    {
        _shouldClose = YES;
    }
    else
    {
        _shouldClose = NO;	/* Keep connection alive */
    }
    
    s = [info objectForKey:NSHTTPPropertyStatusCodeKey];
    _statusCode = [s intValue];
    
    s = [[document headerNamed:@"content-length"] value];
    if ([s length] > 0)
    {
        len = [s intValue];
    }
    
    s = [info objectForKey:NSHTTPPropertyStatusReasonKey];
    enc = [[document headerNamed:@"content-transfer-encoding"] value];
    if (enc == nil)
    {
        enc = [[document headerNamed:@"transfer-encoding"] value];
    }
    /* todo: trasfer encoding support */
    
    info = [document headerNamed:@"content-type"];
    ct = [document contentType];
    st = [document contentSubtype];
    if (ct && st)
    {
        ct = [ct stringByAppendingFormat:@"/%@", st];
    }
    else
    {
        ct = nil;
    }
    _response = [[NSHTTPURLResponse alloc] initWithURL:[this->request URL]
                                              MIMEType:ct
                                 expectedContentLength:len
                                      textEncodingName:[info parameterForKey:@"charset"]];
    [_response _setStatusCode:_statusCode text:s];
    [document deleteHeaderNamed:@"http"];
    [_response _setHeaders:[document allHeaders]];
    
    /* get cookies from the response and accept them into shared storage if policy permits */
    if ([this->request HTTPShouldHandleCookies] == YES && [_response isKindOfClass:[NSHTTPURLResponse class]] == YES)
    {
        NSDictionary *hdrs;
        NSArray *cookies;
        NSURL *url;
        
        url = [_response URL];
        hdrs = [_response allHeaderFields];
        cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:hdrs forURL:url];
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies
                                                           forURL:url
                                                  mainDocumentURL:[this->request mainDocumentURL]];
    }
    /* get redirect location, if any */
    if ((s = [[document headerNamed:@"location"] value]) != nil)
    {
        NSURL *url = [NSURL URLWithString:s];
        
        if (url == nil)
        {   
            if (error != nil)
            {
                *error = [self _errorWithCode:NSURLErrorBadServerResponse description:@"Invalid redirect URL"];
            }
            return NO;
        }
        
        NSMutableURLRequest	*request = [this->request mutableCopy];
        [request setURL: url];
        *aRequest = [request autorelease];
        return YES;
    }
    
#if	USE_ZLIB
    s = [[document headerNamed:@"content-encoding"] value];
    if ([s isEqualToString:@"gzip"] || [s isEqualToString:@"x-gzip"])
    {
        this->decompressing = YES;
        this->z.opaque = 0;
        this->z.zalloc = zalloc;
        this->z.zfree = zfree;
        this->z.next_in = 0;
        this->z.avail_in = 0;
        inflateInit2(&this->z, 1);	// FIXME
    }
#endif
    return YES;
}

- (NSString *)_wwwAuthenticate
{
    return [[[_parser mimeDocument] headerNamed:@"WWW-Authenticate"] value];
}

- (NSURLAuthenticationChallenge *)_handleAuthenticationChallenge
{
    NSInteger   failures = 0;
    
    NSURL *url = [this->request URL];
    NSURLProtectionSpace *space = [GSHTTPAuthentication protectionSpaceForAuthentication:[self _wwwAuthenticate] requestURL:url];
    DESTROY(_credential);	
    if (space != nil)
    {
        /*
         * Create credential from user and password stored in the URL.
         * Returns nil if we have no username or password.
         */
        _credential = [[NSURLCredential alloc] initWithUser:[url user]
                                                   password:[url password]
                                                persistence:NSURLCredentialPersistenceForSession];
        if (_credential == nil)
        {
            /* No credential from the URL, so we try using the default credential for the protection space */
            ASSIGN(_credential, [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space]);
        }
    }
    
    if (_challenge != nil)
    {
        /*
         * The failure count is incremented if we have just
         * tried a request in the same protection space.
         */
        if (YES == [[_challenge protectionSpace] isEqual: space])
        {
            failures = [_challenge previousFailureCount] + 1; 
        }
    }
    else if ([this->request valueForHTTPHeaderField:@"Authorization"])
    {
        /*
         * Our request had an authorization header, so we should
         * count that as a failure or we wouldn't have been
         * challenged.
         */
        failures = 1;
    }
    DESTROY(_challenge);
    
    _challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                            proposedCredential:_credential
                                                          previousFailureCount:failures
                                                               failureResponse:_response
                                                                         error:nil
                                                                        sender:self];
    
    /* Allow the client to control the credential we send or whether we actually send at all */
    return _challenge;
}

- (BOOL)_fulfillAuthenticationRequest:(NSURLRequest **)aRequest error:(NSError **)error
{
    *aRequest = nil;
    if (_challenge == nil)
    {
        /* The client cancelled the authentication challenge so we must cancel the download */
        if (error != nil) {
            *error = [self _errorWithCode:NSURLErrorUserCancelledAuthentication description:@"Authentication cancelled"];
        }
        return NO;
    }
    
    NSString *auth = nil;
    if (_credential != nil)
    {
        NSString *wwwAuthenticate = [self _wwwAuthenticate];
        NSURL *url = [this->request URL];
        NSURLProtectionSpace *space = [GSHTTPAuthentication protectionSpaceForAuthentication:wwwAuthenticate requestURL:url];
        
        /* Get information about basic or digest authentication */
        GSHTTPAuthentication *authentication = [GSHTTPAuthentication authenticationWithCredential:_credential
                                                                                inProtectionSpace:space];
        
        /* Generate authentication header value for the authentication type in the challenge */
        auth = [authentication authorizationForAuthentication:wwwAuthenticate
                                                       method:[this->request HTTPMethod]
                                                         path:[url fullPath]];
    }
    
    if (auth == nil)
    {
        return YES;
    }
    
    /*
     * To answer the authentication challenge, we must retry 
     * with a modified request and with the cached response cleared.
     */
    NSMutableURLRequest	*request = [this->request mutableCopy];
    [request setValue:auth forHTTPHeaderField:@"Authorization"];
    *aRequest = [request autorelease];
    
    return YES;
}

- (NSData *)_handleBody
{
    /* Report partial data if possible */
    NSData *data = [_parser data];
    NSUInteger bodyLength = [data length];
    if (bodyLength > _parseOffset)
    {
        if (_parseOffset > 0)
        {
            data = [data subdataWithRange:NSMakeRange(_parseOffset, [data length] - _parseOffset)];
        }
        _parseOffset = bodyLength;
        return data;
    }
    return nil;
}

- (void)_handleFinish
{
    [self stopLoading];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event
{    
#if 0
    NSLog(@"stream: %@ handleEvent: %x for: %@ (ip %p, op %p)", stream, event, self, this->input, this->output);
#endif
    
    if (stream == this->input)
    {
        switch(event)
        {
            case NSStreamEventHasBytesAvailable: 
            case NSStreamEventEndEncountered:
                [self _got: stream];
                return;
                
            case NSStreamEventOpenCompleted: 
                if (_debug == YES)
                {
                    NSLog(@"%@ HTTP input stream opened", self);
                }
                return;
                
            default: 
                break;
        }
    }
    else if (stream == this->output)
    {
        switch(event)
        {
            case NSStreamEventOpenCompleted: 
            {
                NSMutableString	*m;
                NSDictionary	*d;
                NSEnumerator	*e;
                NSString		*s;
                NSURL		*u;
                NSInteger		l;		
                
                if (_debug == YES)
                {
                    NSLog(@"%@ HTTP output stream opened", self);
                }
                DESTROY(_writeData);
                _writeOffset = 0;
                if ([this->request HTTPBodyStream] == nil)
                {
                    // Not streaming
                    l = [[this->request HTTPBody] length];
                    _version = 1.1;
                }
                else
                {
                    // Stream and close
                    l = -1;
                    _version = 1.0;
                    _shouldClose = YES;
                }
                
                m = [[NSMutableString alloc] initWithCapacity: 1024];
                
                /* The request line is of the form:
                 * method /path?query HTTP/version
                 * where the query part may be missing
                 */
                [m appendString: [this->request HTTPMethod]];
                [m appendString: @" "];
                u = [this->request URL];
                s = [[u fullPath] stringByAddingPercentEscapesUsingEncoding:
                     NSUTF8StringEncoding];
                if ([s hasPrefix: @"/"] == NO)
                {
                    [m appendString: @"/"];
                }
                [m appendString: s];
                s = [u query];
                if ([s length] > 0)
                {
                    [m appendString: @"?"];
                    [m appendString: s];
                }
                [m appendFormat: @" HTTP/%0.1f\r\n", _version];
                
                d = [this->request allHTTPHeaderFields];
                e = [d keyEnumerator];
                while ((s = [e nextObject]) != nil)
                {
                    [m appendString: s];
                    [m appendString: @": "];
                    [m appendString: [d objectForKey: s]];
                    [m appendString: @"\r\n"];
                }
                /* Use valueForHTTPHeaderField: to check for content-type
                 * header as that does a case insensitive comparison and
                 * we therefore won't end up adding a second header by
                 * accident because the two header names differ in case.
                 */
                if ([[this->request HTTPMethod] isEqual: @"POST"] && [this->request valueForHTTPHeaderField:@"Content-Type"] == nil)
                {
                    /* On MacOSX, this is automatically added to POST methods */
                    [m appendString:@"Content-Type: application/x-www-form-urlencoded\r\n"];
                }
                if ([this->request valueForHTTPHeaderField: @"Host"] == nil)
                {
                    id	p = [u port];
                    id	h = [u host];
                    
                    if (h == nil)
                    {
                        h = @"";	// Must send an empty host header
                    }
                    if (p == nil)
                    {
                        [m appendFormat: @"Host: %@\r\n", h];
                    }
                    else
                    {
                        [m appendFormat: @"Host: %@:%@\r\n", h, p];
                    }
                }
                if (l >= 0 && [this->request valueForHTTPHeaderField: @"Content-Length"] == nil)
                {
                    [m appendFormat: @"Content-Length: %d\r\n", l];
                }
                [m appendString: @"\r\n"];	// End of headers
                _writeData = RETAIN([m dataUsingEncoding: NSASCIIStringEncoding]);
                RELEASE(m);
            }			// Fall through to do the write
                
            case NSStreamEventHasSpaceAvailable: 
            {
                NSInteger	written;
                BOOL	sent = NO;
                
                // FIXME: should also send out relevant Cookies
                if (_writeData != nil)
                {
                    const unsigned char	*bytes = [_writeData bytes];
                    NSUInteger len = [_writeData length];
                    
                    written = [this->output write:bytes + _writeOffset maxLength:len - _writeOffset];
                    if (written > 0)
                    {
                        if (_debug == YES)
                        {
                            NSLog(@"%@ wrote %ld bytes: '%*.*s'", self, (long)written, (int)written, (int)written, bytes + _writeOffset);
                        }
                        _writeOffset += written;
                        if (_writeOffset >= len)
                        {
                            DESTROY(_writeData);
                            if (_body == nil)
                            {
                                _body = RETAIN([this->request HTTPBodyStream]);
                                if (_body == nil)
                                {
                                    NSData	*data = [this->request HTTPBody];
                                    
                                    if (data != nil)
                                    {
                                        _body = [NSInputStream alloc];
                                        _body = [_body initWithData:data];
                                        [_body open];
                                    }
                                    else
                                    {
                                        sent = YES;
                                    }
                                }
                            }
                        }
                    }
                }
                else if (_body != nil)
                {
                    if ([_body hasBytesAvailable])
                    {
                        unsigned char   buffer[BUFSIZ*64];
                        NSInteger       len;
                        
                        len = [_body read:buffer maxLength:sizeof(buffer)];
                        if (len < 0)
                        {
                            if (_debug == YES)
                            {
                                NSLog(@"%@ error reading from HTTPBody stream %@", self, [NSError _last]);
                            }
                            [self stopLoading];
                            [this->client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"can't read body" code:0 userInfo:nil]];
                            return;
                        }
                        else if (len > 0)
                        {
                            written = [this->output write:buffer maxLength:len];
                            if (written > 0)
                            {
                                if (_debug == YES)
                                {
                                    NSLog(@"%@ wrote %ld bytes: '%*.*s'", self, (long)written, (int)written, (int)written, buffer);
                                }
                                len -= written;
                                if (len > 0)
                                {
                                    /* Couldn't write it all now, save and try
                                     * again later.
                                     */
                                    _writeData = [[NSData alloc] initWithBytes:buffer + written length:len];
                                    _writeOffset = 0;
                                }
                            }
                            else if ([this->output streamStatus] == NSStreamStatusWriting)
                            {
                                /* Couldn't write it all now, save and try again later */
                                _writeData = [[NSData alloc] initWithBytes:buffer length:len];
                                _writeOffset = 0;
                            }
                        }
                        else
                        {
                            [_body close];
                            DESTROY(_body);
                            sent = YES;
                        }
                    }
                    else
                    {
                        [_body close];
                        DESTROY(_body);
                        sent = YES;
                    }
                }
                if (sent == YES)
                {
                    if (_debug)
                    {
                        NSLog(@"%@ request sent", self);
                    }
                }
                return;  // done
            }
            default: 
                break;
        }
    }
    else
    {
        NSLog(@"Unexpected event %"PRIuPTR" occurred on stream %@ not being used by %@", event, stream, self);
    }
    if (event == NSStreamEventErrorOccurred)
    {
        NSError	*error = [[[stream streamError] retain] autorelease];
        
        [self stopLoading];
        [this->client URLProtocol: self didFailWithError: error];
    }
    else
    {
        NSLog(@"Unexpected event %"PRIuPTR" ignored on stream %@ of %@", event, stream, self);
    }
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge == _challenge)
    {
        ASSIGN(_credential, credential);
    }
}

@end

@implementation _NSHTTPSURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
  return [[[request URL] scheme] isEqualToString:@"https"];
}

@end

@implementation _NSFTPURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
  return [[[request URL] scheme] isEqualToString:@"ftp"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
  return request;
}

- (void)startLoading
{
    if (this->cachedResponse)
    { 
        // todo: handle from cache
    }
    else
    {
        NSURL	*url = [this->request URL];
        NSHost	*host = [NSHost hostWithName:[url host]];
        
        if (host == nil)
        {
            host = [NSHost hostWithAddress:[url host]];
        }
        [NSStream getStreamsToHost:host
                              port:[[url port] intValue]
                       inputStream:&this->input
                      outputStream:&this->output];
        if (this->input == nil || this->output == nil)
        {
            NSError *error = [NSError errorWithDomain:@"can't connect" code:0 userInfo:nil];
            [this->client URLProtocol:self didFailWithError:error];
            return;
        }
#if	!GS_WITH_GC
        [this->input retain];
        [this->output retain];
#endif
        if ([[url scheme] isEqualToString: @"https"] == YES)
        {
            [this->input setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                              forKey: NSStreamSocketSecurityLevelKey];
            [this->output setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                               forKey: NSStreamSocketSecurityLevelKey];
        }
        [this->input setDelegate:self];
        [this->output setDelegate:self];
        [this->input scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [this->output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        /* set socket options for ftps requests */
        [this->input open];
        [this->output open];
    }
}

- (void)stopLoading
{
    if (this->input)
    {
        [this->input setDelegate:nil];
        [this->output setDelegate:nil];
        [this->input removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [this->output removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [this->input close];
        [this->output close];
        DESTROY(this->input);
        DESTROY(this->output);
    }
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event
{
    if (stream == this->input) 
    {
        switch(event)
        {
            case NSStreamEventHasBytesAvailable: 
            {
                NSLog(@"FTP input stream has bytes available");
                // todo: implement FTP protocol
                // [this->client URLProtocol: self didLoadData: [NSData dataWithBytes: buffer length: len]];
                return;
            }
            case NSStreamEventEndEncountered: 	// can this occur in parallel to NSStreamEventHasBytesAvailable???
                NSLog(@"FTP input stream did end");
                [this->client URLProtocolDidFinishLoading: self];
                return;
            case NSStreamEventOpenCompleted: 
                // prepare to receive header
                NSLog(@"FTP input stream opened");
                return;
            default: 
                break;
        }
    }
    else if (stream == this->output)
    {
        NSLog(@"An event occurred on the output stream.");
        /* if successfully opened, send out FTP request header */
    }
    else
    {
        NSLog(@"Unexpected event %"PRIuPTR" occurred on stream %@ not being used by %@", event, stream, self);
    }
    if (event == NSStreamEventErrorOccurred)
    {
        NSLog(@"An error %@ occurred on stream %@ of %@", [stream streamError], stream, self);
        [self stopLoading];
        [this->client URLProtocol: self didFailWithError: [stream streamError]];
    }
    else
    {
        NSLog(@"Unexpected event %"PRIuPTR" ignored on stream %@ of %@", event, stream, self);
    }
}

@end

@implementation _NSFileURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"file"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) startLoading
{
  // check for GET/PUT/DELETE etc so that we can also write to a file
  NSData	*data;
  NSURLResponse	*r;

  data = [NSData dataWithContentsOfFile: [[this->request URL] path]
  /* options: error: - don't use that because it is based on self */];
  if (data == nil)
    {
      [this->client URLProtocol: self didFailWithError:
	[NSError errorWithDomain: @"can't load file" code: 0 userInfo:
	  [NSDictionary dictionaryWithObjectsAndKeys: 
	    [this->request URL], @"URL",
	    [[this->request URL] path], @"path",
	    nil]]];
      return;
    }

  /* FIXME ... maybe should infer MIME type and encoding from extension or BOM
   */
  r = [[NSURLResponse alloc] initWithURL: [this->request URL]
				MIMEType: @"text/html"
		   expectedContentLength: [data length]
			textEncodingName: @"unknown"];	
  [this->client URLProtocol: self
    didReceiveResponse: r
    cacheStoragePolicy: NSURLRequestUseProtocolCachePolicy];
  [this->client URLProtocol: self didLoadData: data];
  [this->client URLProtocolDidFinishLoading: self];
  RELEASE(r);
}

- (void) stopLoading
{
  return;
}

@end

@implementation _NSAboutURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"about"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) startLoading
{
  NSURLResponse	*r;
  NSData	*data = [NSData data];	// no data

  // we could pass different content depending on the url path
  r = [[NSURLResponse alloc] initWithURL: [this->request URL]
				MIMEType: @"text/html"
		   expectedContentLength: 0
			textEncodingName: @"utf-8"];	
  [this->client URLProtocol: self
    didReceiveResponse: r
    cacheStoragePolicy: NSURLRequestUseProtocolCachePolicy];
  [this->client URLProtocol: self didLoadData: data];
  [this->client URLProtocolDidFinishLoading: self];
  RELEASE(r);
}

- (void) stopLoading
{
  return;
}

@end
