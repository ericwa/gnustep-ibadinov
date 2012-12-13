/** Implementation for GSFileHandle for GNUStep
   Copyright (C) 1997-2002 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: 1997, 2002

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

#define	_FILE_OFFSET_BITS 64

#import "common.h"
#define	EXPOSE_NSFileHandle_IVARS	1
#define	EXPOSE_GSFileHandle_IVARS	1
#import "Foundation/NSData.h"
#import "Foundation/NSArray.h"
#import "Foundation/NSFileHandle.h"
#import "Foundation/NSException.h"
#import "Foundation/NSRunLoop.h"
#import "Foundation/NSNotification.h"
#import "Foundation/NSNotificationQueue.h"
#import "Foundation/NSHost.h"
#import "Foundation/NSByteOrder.h"
#import "Foundation/NSProcessInfo.h"
#import "Foundation/NSUserDefaults.h"
#import "GSPrivate.h"
#import "GSNetwork.h"
#import "GNUstepBase/NSObject+GNUstepBase.h"
#import "GSFileHandle.h"
#import "GSSocksParser/GSSocksParser.h"

#import "../Tools/gdomap.h"

#include <time.h>
#include <sys/time.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#if	defined(HAVE_SYS_FILE_H)
#  include	<sys/file.h>
#endif

#include <sys/stat.h>

#if	defined(HAVE_SYS_FCNTL_H)
#  include	<sys/fcntl.h>
#elif	defined(HAVE_FCNTL_H)
#  include	<fcntl.h>
#endif

#include <sys/ioctl.h>
#ifdef	__svr4__
#  ifdef HAVE_SYS_FILIO_H
#    include <sys/filio.h>
#  endif
#endif
#include <netdb.h>

/*
 *	Stuff for setting the sockets into non-blocking mode.
 */
#if defined(__POSIX_SOURCE)\
        || defined(__EXT_POSIX1_198808)\
        || defined(O_NONBLOCK)
#define NBLK_OPT     O_NONBLOCK
#else
#define NBLK_OPT     FNDELAY
#endif

#ifndef	O_BINARY
#ifdef	_O_BINARY
#define	O_BINARY	_O_BINARY
#else
#define	O_BINARY	0
#endif
#endif

#ifndef	INADDR_NONE
#define	INADDR_NONE	-1
#endif

// Maximum data in single I/O operation
#define	NETBUF_SIZE	4096
#define	READ_SIZE	NETBUF_SIZE*10

static GSFileHandle*	fh_stdin = nil;
static GSFileHandle*	fh_stdout = nil;
static GSFileHandle*	fh_stderr = nil;

static NSString *const SocksConnectNotification = @"SocksConnectNotification";
static NSString *const SocksReadNotification    = @"SocksReadNotification";
static NSString *const SocksWriteNotification   = @"SocksReadNotification";

static NSString *const SocksParserKey = @"SocksParserKey";

static NSString *gsSocks = nil;

// Key to info dictionary for operation mode.
static NSString*	NotificationKey = @"NSFileHandleNotificationKey";

@interface GSFileHandle(private)
- (void) receivedEventRead;
- (void) receivedEventWrite;
@end

#if !defined (__GNUC__)
#  define __builtin_expect(expression, value) expression
#endif

@implementation GSFileHandle

/**
 * Encapsulates low level read operation to get data from the operating
 * system.
 */
- (NSInteger)read:(void *)buf length:(NSUInteger)len
{
    ssize_t	result;
    
#if NSUIntegerMax > UINT_MAX
    if (__builtin_expect(gzDescriptor && len > UINT_MAX, NO)) {
        [NSException raise:NSRangeException format:@"Maximum read size with gzip is %u", UINT_MAX];
    }
#endif
    
    do
    {
#if	USE_ZLIB
        if (gzDescriptor)
        {
            result = gzread(gzDescriptor, buf, (unsigned)len);
        }
        else
#endif
            if (isSocket)
            {
                result = recv(descriptor, buf, len, 0);
            }
            else
            {
                result = read(descriptor, buf, len);
            }
    }
    while (result < 0 && EINTR == errno);
    return result;
}

/**
 * Encapsulates low level write operation to send data to the operating
 * system.
 */
- (NSInteger)write:(const void *)buf length:(NSUInteger)len
{
    ssize_t	result;
    
#if NSUIntegerMax > UINT_MAX
    if (__builtin_expect(gzDescriptor && len > UINT_MAX, NO)) {
        [NSException raise:NSRangeException format:@"Maximum write size with gzip is %u", UINT_MAX];
    }
#endif
    
    do
    {
#if	USE_ZLIB
        if (gzDescriptor != 0)
        {
            result = gzwrite(gzDescriptor, (char *)buf, (unsigned)len);
        }
        else
#endif
            if (isSocket)
            {
                result = send(descriptor, buf, len, 0);
            }
            else
            {
                result = write(descriptor, buf, len);
            }
    }
    while (result < 0 && EINTR == errno);
    return result;
}

+ (id) allocWithZone: (NSZone*)z
{
  return NSAllocateObject ([self class], 0, z);
}

- (void) dealloc
{
  DESTROY(address);
  DESTROY(service);
  DESTROY(protocol);

  [self finalize];

  DESTROY(readInfo);
  DESTROY(writeInfo);
  [super dealloc];
}

- (void) finalize
{
  if (self == fh_stdin)
    fh_stdin = nil;
  if (self == fh_stdout)
    fh_stdout = nil;
  if (self == fh_stderr)
    fh_stderr = nil;

  [self ignoreReadDescriptor];
  [self ignoreWriteDescriptor];

#if	USE_ZLIB
  /*
   * The gzDescriptor should always be closed when we have done with it.
   */
  if (gzDescriptor != 0)
    {
      gzclose(gzDescriptor);
      gzDescriptor = 0;
    }
#endif
  if (descriptor != -1)
    {
      [self setNonBlocking: wasNonBlocking];
      if (closeOnDealloc == YES)
	{
	  close(descriptor);
	  descriptor = -1;
	}
    }
}

// Initializing a GSFileHandle Object

- (id) init
{
  return [self initWithNullDevice];
}

- (void)_setupDescriptor:(int)aDescriptor
{
    struct stat	sbuf;
    int         e;
    
    if (fstat(aDescriptor, &sbuf) < 0) {
#if	defined(__MINGW__)
        /* On windows, an fstat will fail if the descriptor is a pipe
         * or socket, so we simply mark the descriptor as not being a
         * standard file.
         */
        isStandardFile = NO;
#else
        /* This should never happen on unix.  If it does, we have somehow
         * ended up with a bad descriptor.
         */
        NSLog(@"unable to get status of descriptor %d - %@", aDescriptor, [NSError _last]);
        isStandardFile = NO;
#endif
	} else {
        if (S_ISREG(sbuf.st_mode)) {
            isStandardFile = YES;
	    } else {
            isStandardFile = NO;
	    }
	}
    
    if ((e = fcntl(aDescriptor, F_GETFL, 0)) >= 0)	{
        if (e & NBLK_OPT) {
            wasNonBlocking = YES;
	    } else {
            wasNonBlocking = NO;
	    }
	}
    
    isNonBlocking = wasNonBlocking;
    descriptor = aDescriptor;
    readInfo = nil;
    writeInfo = [NSMutableArray new];
    readMax = 0;
    writePos = 0;
    readOK = YES;
    writeOK = YES;
    acceptOK = YES;
    connectOK = YES;
}

- (id) initWithFileDescriptor: (int)desc closeOnDealloc: (BOOL)flag
{
    if (self = [super init]) {
        [self _setupDescriptor:desc];
        closeOnDealloc = flag;
    } else if (flag == YES) {
        close(desc);
    }
    return self;
}

/**
 * Initialise as a client socket connection ... do this by using
 * [-initAsClientInBackgroundAtAddress:service:protocol:forModes:]
 * and running the current run loop in NSDefaultRunLoopMode until
 * the connection attempt succeeds, fails, or times out.
 */
- (id) initAsClientAtAddress: (NSString*)a
		     service: (NSString*)s
		    protocol: (NSString*)p
{
  self = [self initAsClientInBackgroundAtAddress: a
					 service: s
					protocol: p
					forModes: nil];
  if (self != nil)
    {
      NSRunLoop	*loop;
      NSDate	*limit;

      loop = [NSRunLoop currentRunLoop];
      limit = [NSDate dateWithTimeIntervalSinceNow: 300];
      while ([limit timeIntervalSinceNow] > 0
	&& (readInfo != nil || [writeInfo count] > 0))
	{
	  [loop runMode: NSDefaultRunLoopMode
	     beforeDate: limit];
	}
      if (readInfo != nil || [writeInfo count] > 0 || readOK == NO)
	{
	  /* Must have timed out or failed */
	  DESTROY(self);
	}
      else
	{
	  [self setNonBlocking: NO];
	}
    }
  return self;
}

- (BOOL)_connectToService:(NSString *)aService
                   atHost:(NSString *)aHost
            usingProtocol:(NSString *)aProtocol
              fromAddress:(NSString *)localAddress
                  service:(NSString *)localService
      observeNotification:(NSString *)aName
                 forModes:(NSArray  *)aModes
{
    if (descriptor >= 0) {
        if (closeOnDealloc) {
            close(descriptor);
        }
        descriptor = -1;
    }
    
    struct sockaddr socketAddress;
    
    if (!GSPrivateSockaddrSetup(aHost, 0, aService, aProtocol, &socketAddress)) {
        NSLog(@"bad address-service-protocol combination");
        return NO;
    }
    [self setAddr:&socketAddress]; /* Store the address of the remote end */
    
    /* Don't use SOCKS if we are contacting the local host */
    
    if ((descriptor = socket(socketAddress.sa_family, SOCK_STREAM, PF_UNSPEC)) == -1) {
        NSLog(@"unable to create socket - %@", [NSError _last]);
        return NO;
    }
    
    /* Enable tcp-level tracking of whether connection is alive */
    int status = 1;
    setsockopt(descriptor, SOL_SOCKET, SO_KEEPALIVE, (char *)&status, sizeof(status));
    
    if (localAddress) {
        struct sockaddr localSocketAddress;
        if (!GSPrivateSockaddrSetup(localAddress, 0, localService, aProtocol, &localSocketAddress)) {
            NSLog(@"bad bind address specification");
            return NO;
        }
        if (bind(descriptor, &localSocketAddress, GSPrivateSockaddrLength(&localSocketAddress)) == -1)
        {
            NSLog(@"unable to bind to socket to address %@ - %@", GSPrivateSockaddrName(&localSocketAddress), [NSError _last]);
            return NO;
        }
    }
    
    [self _setupDescriptor:descriptor];
    
    NSMutableDictionary*	info;
    isSocket = YES;
    [self setNonBlocking: YES];
    if (connect(descriptor, &socketAddress, GSPrivateSockaddrLength(&socketAddress)) == -1) {
        if (!GSWOULDBLOCK) {
            NSLog(@"unable to make socket connection to %@ - %@", GSPrivateSockaddrName(&socketAddress), [NSError _last]);
            return NO;
        }
    }
    
    info = [[NSMutableDictionary alloc] initWithCapacity:4];
    [info setObject:address forKey:NSFileHandleNotificationDataItem];
    [info setObject:aName forKey:NotificationKey];
    if (aModes) {
        [info setObject:aModes forKey:NSFileHandleNotificationMonitorModes];
    }
    [writeInfo addObject:info];
    RELEASE(info);
    [self watchWriteDescriptor];
    connectOK = YES;
    acceptOK = NO;
    readOK = NO;
    writeOK = NO;
    
    return YES;
}

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    gsSocks = [[defaults stringForKey:@"GSSOCKS"] copy];
    if (!gsSocks) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        gsSocks = [[environment objectForKey:@"SOCKS5_SERVER"] copy];
        if (!gsSocks) {
            gsSocks = [[environment objectForKey:@"SOCKS_SERVER"] copy];
        }
    }
}

- (id)initAsClientInBackgroundAtAddress:(NSString *)anAddress
                                service:(NSString *)aService
                               protocol:(NSString *)aProtocol
                               forModes:(NSArray  *)modes
{
    if (!(self = [self init])) {
        return nil;
    }
    
    if (!anAddress || ![anAddress length]) {
        anAddress = @"localhost";
    }
    if (!aService) {
        NSLog(@"bad argument - service is nil");
        DESTROY(self);
        return nil;
    }
    
    NSString *socksHost = nil;
    NSString *socksPort = nil;
    if ([aProtocol hasPrefix:@"socks-"]) {
        socksHost = [aProtocol substringFromIndex:6];
    } else if (gsSocks) {
        socksHost = gsSocks;
    }
    if (socksHost && [socksHost length]) {
        NSRange range = [socksHost rangeOfString:@":"];
        if (range.location != NSNotFound) {
            socksPort = [socksHost substringFromIndex:NSMaxRange(range)];
            socksHost = [socksHost substringToIndex:range.location];
        } else
            socksPort = @"1080";
        aProtocol = @"tcp";
        
        NSHost *host = [NSHost hostWithName:socksHost];
        if ([host isEqualToHost:[NSHost currentHost]] || [host isEqualToHost:[NSHost localHost]]) {
            socksHost = socksPort = nil;
        }
    }
    
    
    NSString *localAddress = nil;
    NSString *localService = nil;
    if ([aProtocol hasPrefix:@"bind-"]) {
        localAddress = [aProtocol substringFromIndex:5];
        
        NSRange range = [aProtocol rangeOfString:@":"];
        if (range.location != NSNotFound) {
            localService = [localAddress substringFromIndex:NSMaxRange(range)];
            localAddress = [localAddress substringToIndex:range.location];
        }
        
        aProtocol = @"tcp";
    }
    
    address = [anAddress retain];
    service = [aService retain];
    
    NSString *dstHost = socksHost ? socksHost : anAddress;
    NSString *dstService = socksPort ? socksPort : aService;
    NSString *notification = socksHost ? SocksConnectNotification : GSFileHandleConnectCompletionNotification;
    
    BOOL connected = [self _connectToService:dstService
                                      atHost:dstHost
                               usingProtocol:aProtocol
                                 fromAddress:localAddress
                                     service:localService
                         observeNotification:notification
                                    forModes:modes];
    closeOnDealloc = YES;
    if (!connected) {
        DESTROY(self);
        return nil;
    }
    return self;
}

- (void)_postNotificationWithInfo:(NSDictionary *)userInfo
{
    NSNotification *noification = [NSNotification notificationWithName:[userInfo objectForKey:NotificationKey]
                                                                object:self
                                                              userInfo:userInfo];

    [[NSNotificationQueue defaultQueue] enqueueNotification:noification
                                               postingStyle:NSPostASAP
                                               coalesceMask:NSNotificationNoCoalescing
                                                   forModes:[userInfo objectForKey:NSFileHandleNotificationMonitorModes]];
}

- (void)_postNotificationWithSocksError:(NSString *)error
                               userInfo:(NSDictionary *)userInfo
{
    NSDebugMLLog(@"NSFileHandle", @"%@ SOCKS error: %@", self, error);
    
    /* Error in the initial connection. Notify everybody */
    NSMutableDictionary *info = [userInfo mutableCopy];
    [info setObject:GSFileHandleConnectCompletionNotification forKey:NotificationKey];
    [info setObject:error forKey:GSFileHandleNotificationError];
    
    [self _postNotificationWithInfo:info];
    RELEASE(info);
}

- (void)_handleSocksNotification:(NSNotification *)aNotification
{
    NSString *notificationName = [aNotification name];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:notificationName
                                                  object:self];
    
    NSDictionary *userInfo = [aNotification userInfo];
    NSString *error = [userInfo objectForKey:GSFileHandleNotificationError];
    if (error) {
        [self _postNotificationWithSocksError:error userInfo:userInfo];
    }
    
    if (notificationName == SocksConnectNotification) { 
        NSDictionary *configuration = [NSDictionary dictionaryWithObject:NSStreamSOCKSProxyVersion5 forKey:NSStreamSOCKSProxyVersionKey];
        GSSocksParser *parser = [[GSSocksParser alloc] initWithConfiguration:configuration
                                                                     address:address
                                                                        port:[service integerValue]];
        [readInfo setObject:parser forKey:SocksParserKey];
        
        [parser start];
        RELEASE(parser);
    } else if (notificationName == SocksReadNotification) {
        NSData *chunk = [userInfo objectForKey:NSFileHandleNotificationDataItem];
        if (![chunk length]) {
            [self _postNotificationWithSocksError:@"Connection to SOCKS server has been closed prematurely"
                                         userInfo:userInfo];
            return;
        }
        GSSocksParser *parser = [readInfo objectForKey:SocksParserKey];
        [parser parseNextChunk:chunk];
    }
}

- (void)parser:(GSSocksParser *)aParser needsMoreBytes:(NSUInteger)aLength
{
    [self readDataInBackgroundAndNotifyLength:aLength];
    [readInfo setObject:SocksReadNotification forKey:NotificationKey];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleSocksNotification:)
                                                 name:SocksReadNotification
                                               object:self];
}

- (void)parser:(GSSocksParser *)aParser formedRequest:(NSData *)aRequest
{
    [self writeInBackgroundAndNotify:aRequest];
    
    [[writeInfo lastObject] setObject:SocksWriteNotification forKey:NotificationKey];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleSocksNotification:)
                                                 name:SocksWriteNotification
                                               object:self];
}

- (void)parser:(GSSocksParser *)aParser finishedWithAddress:(NSString *)anAddress port:(NSUInteger)aPort
{
    [[readInfo objectForKey:SocksParserKey] setDelegate:nil];
    [readInfo removeObjectForKey:SocksParserKey];
    if (anAddress == address && aPort == [service integerValue]) {
        /* Success. Notify everybody */
        NSMutableDictionary *info = [readInfo mutableCopy];
        [info setObject:GSFileHandleConnectCompletionNotification forKey:NotificationKey];
        
        [self _postNotificationWithInfo:info];
        RELEASE(info);
    } else {
        BOOL connected = [self _connectToService:[NSString stringWithFormat:@"ld", (long)aPort]
                                          atHost:anAddress
                                   usingProtocol:@"tcp"
                                     fromAddress:[self socketLocalAddress]
                                         service:[self socketLocalService]
                             observeNotification:GSFileHandleConnectCompletionNotification
                                        forModes:[readInfo objectForKey:NSFileHandleNotificationMonitorModes]];
        if (!connected) {
            [self _postNotificationWithSocksError:@"Failed to reconnect to SOCKS server"
                                         userInfo:readInfo];
        }
    }
}

- (void)parser:(GSSocksParser *)aParser encounteredError:(NSError *)anError
{
    NSMutableDictionary *info = [readInfo mutableCopy];
    [info setObject:GSFileHandleConnectCompletionNotification forKey:NotificationKey];
    [info setObject:anError forKey:@"NSFileHandleError"];
    
    [self _postNotificationWithInfo:info];
    RELEASE(info);
}

- (id) initAsServerAtAddress: (NSString*)a
		     service: (NSString*)s
		    protocol: (NSString*)p
{
#ifndef	BROKEN_SO_REUSEADDR
  int			status = 1;
#endif
  int			net;
  struct sockaddr	sin;
  unsigned int		size = sizeof(sin);

  if (GSPrivateSockaddrSetup(a, 0, s, p, &sin) == NO)
    {
      DESTROY(self);
      NSLog(@"bad address-service-protocol combination");
      return  nil;
    }

  if ((net = socket(sin.sa_family, SOCK_STREAM, PF_UNSPEC)) == -1)
    {
      NSLog(@"unable to create socket - %@", [NSError _last]);
      DESTROY(self);
      return nil;
    }

#ifndef	BROKEN_SO_REUSEADDR
  /*
   * Under decent systems, SO_REUSEADDR means that the port can be reused
   * immediately that this process exits.  Under some it means
   * that multiple processes can serve the same port simultaneously.
   * We don't want that broken behavior!
   */
  setsockopt(net, SOL_SOCKET, SO_REUSEADDR, (char *)&status, sizeof(status));
#endif

  if (bind(net, &sin, GSPrivateSockaddrLength(&sin)) == -1)
    {
      NSError	*e = [NSError _last];

      NSLog(@"unable to bind to port %@ - %@",
	GSPrivateSockaddrName(&sin), e);
      (void) close(net);
      DESTROY(self);
      return nil;
    }

  /* We try to allow a large number of connections.
   */
  if (listen(net, GSBACKLOG) == -1)
    {
      NSLog(@"unable to listen on port - %@", [NSError _last]);
      (void) close(net);
      DESTROY(self);
      return nil;
    }

  if (getsockname(net, &sin, &size) == -1)
    {
      NSLog(@"unable to get socket name - %@", [NSError _last]);
      (void) close(net);
      DESTROY(self);
      return nil;
    }

  self = [self initWithFileDescriptor: net closeOnDealloc: YES];
  if (self)
    {
      isSocket = YES;
      connectOK = NO;
      acceptOK = YES;
      readOK = NO;
      writeOK = NO;
      [self setAddr: &sin];
    }
  return self;
}

- (id) initForReadingAtPath: (NSString*)path
{
  int	d = open([path fileSystemRepresentation], O_RDONLY|O_BINARY);

  if (d < 0)
    {
      DESTROY(self);
      return nil;
    }
  else
    {
      self = [self initWithFileDescriptor: d closeOnDealloc: YES];
      if (self)
	{
	  connectOK = NO;
	  acceptOK = NO;
	  writeOK = NO;
	}
      return self;
    }
}

- (id) initForWritingAtPath: (NSString*)path
{
  int	d = open([path fileSystemRepresentation], O_WRONLY|O_BINARY);

  if (d < 0)
    {
      DESTROY(self);
      return nil;
    }
  else
    {
      self = [self initWithFileDescriptor: d closeOnDealloc: YES];
      if (self)
	{
	  connectOK = NO;
	  acceptOK = NO;
	  readOK = NO;
	}
      return self;
    }
}

- (id) initForUpdatingAtPath: (NSString*)path
{
  int	d = open([path fileSystemRepresentation], O_RDWR|O_BINARY);

  if (d < 0)
    {
      DESTROY(self);
      return nil;
    }
  else
    {
      self = [self initWithFileDescriptor: d closeOnDealloc: YES];
      if (self != nil)
	{
	  connectOK = NO;
	  acceptOK = NO;
	}
      return self;
    }
}

- (id) initWithStandardError
{
  if (fh_stderr != nil)
    {
      ASSIGN(self, fh_stderr);
    }
  else
    {
      self = [self initWithFileDescriptor: 2 closeOnDealloc: NO];
      fh_stderr = self;
      if (self)
	{
	  readOK = NO;
	}
    }
  return self;
}

- (id) initWithStandardInput
{
  if (fh_stdin != nil)
    {
      ASSIGN(self, fh_stdin);
    }
  else
    {
      self = [self initWithFileDescriptor: 0 closeOnDealloc: NO];
      fh_stdin = self;
      if (self)
	{
	  writeOK = NO;
	}
    }
  return self;
}

- (id) initWithStandardOutput
{
  if (fh_stdout != nil)
    {
      ASSIGN(self, fh_stdout);
    }
  else
    {
      self = [self initWithFileDescriptor: 1 closeOnDealloc: NO];
      fh_stdout = self;
      if (self)
	{
	  readOK = NO;
	}
    }
  return self;
}

- (id) initWithNullDevice
{
  self = [self initWithFileDescriptor: open("/dev/null", O_RDWR|O_BINARY)
		       closeOnDealloc: YES];
  if (self)
    {
      isNullDevice = YES;
    }
  return self;
}

- (id) initWithNativeHandle: (void*)hdl
{
  return [self initWithFileDescriptor: (int)hdl closeOnDealloc: NO];
}

- (id) initWithNativeHandle: (void*)hdl closeOnDealloc: (BOOL)flag
{
  return [self initWithFileDescriptor: (int)hdl closeOnDealloc: flag];
}

- (void) checkAccept
{
  if (acceptOK == NO)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"accept not permitted in this file handle"];
    }
  if (readInfo)
    {
      id	operation = [readInfo objectForKey: NotificationKey];

      if (operation == NSFileHandleConnectionAcceptedNotification)
        {
          [NSException raise: NSFileHandleOperationException
                      format: @"accept already in progress"];
	}
      else
	{
          [NSException raise: NSFileHandleOperationException
                      format: @"read already in progress"];
	}
    }
}

- (void) checkConnect
{
  if (connectOK == NO)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"connect not permitted in this file handle"];
    }
  if ([writeInfo count] > 0)
    {
      NSDictionary	*info = [writeInfo objectAtIndex: 0];
      id		operation = [info objectForKey: NotificationKey];

      if (operation == GSFileHandleConnectCompletionNotification)
	{
          [NSException raise: NSFileHandleOperationException
                      format: @"connect already in progress"];
	}
      else
	{
          [NSException raise: NSFileHandleOperationException
                      format: @"write already in progress"];
	}
    }
}

- (void) checkRead
{
  if (readOK == NO)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"read not permitted on this file handle"];
    }
  if (readInfo)
    {
      id	operation = [readInfo objectForKey: NotificationKey];

      if (operation == NSFileHandleConnectionAcceptedNotification)
        {
          [NSException raise: NSFileHandleOperationException
                      format: @"accept already in progress"];
	}
      else
	{
          [NSException raise: NSFileHandleOperationException
                      format: @"read already in progress"];
	}
    }
}

- (void) checkWrite
{
  if (writeOK == NO)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"write not permitted in this file handle"];
    }
  if ([writeInfo count] > 0)
    {
      NSDictionary	*info = [writeInfo objectAtIndex: 0];
      id		operation = [info objectForKey: NotificationKey];

      if (operation != GSFileHandleWriteCompletionNotification)
	{
          [NSException raise: NSFileHandleOperationException
                      format: @"connect in progress"];
	}
    }
}

// Returning file handles

- (int) fileDescriptor
{
  return descriptor;
}

- (void*) nativeHandle
{
  return (void*)(intptr_t)descriptor;
}

// Synchronous I/O operations

- (NSData*) availableData
{
  char buf[READ_SIZE];
  NSMutableData*	d;
  NSInteger       len;

  [self checkRead];
  d = [NSMutableData dataWithCapacity: 0];
  if (isStandardFile)
    {
      if (isNonBlocking == YES)
	{
	  [self setNonBlocking: NO];
	}
      while ((len = [self read: buf length: sizeof(buf)]) > 0)
        {
	  [d appendBytes: buf length: len];
        }
    }
  else
    {
      if (isNonBlocking == NO)
	{
	  [self setNonBlocking: YES];
	}
      len = [self read: buf length: sizeof(buf)];

      if (len <= 0)
	{
	  if (errno == EAGAIN || errno == EINTR)
	    {
	      /*
	       * Read would have blocked ... so try to get a single character
	       * in non-blocking mode (to ensure we wait until data arrives)
	       * and then try again.
	       * This ensures that we block for *some* data as we should.
	       */
	      [self setNonBlocking: NO];
	      len = [self read: buf length: 1];
	      [self setNonBlocking: YES];
	      if (len == 1)
		{
		  len = [self read: &buf[1] length: sizeof(buf) - 1];
		  if (len <= 0)
		    {
		      len = 1;
		    }
		  else
		    {
		      len = len + 1;
		    }
		}
	    }
	}

      if (len > 0)
	{
	  [d appendBytes: buf length: len];
	}
    }
  if (len < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"unable to read from descriptor - %@",
                  [NSError _last]];
    }
  return d;
}

- (NSData*) readDataToEndOfFile
{
  char buf[READ_SIZE];
  NSMutableData*	d;
  NSInteger       len;

  [self checkRead];
  if (isNonBlocking == YES)
    {
      [self setNonBlocking: NO];
    }
  d = [NSMutableData dataWithCapacity: 0];
  while ((len = [self read: buf length: sizeof(buf)]) > 0)
    {
      [d appendBytes: buf length: len];
    }
  if (len < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"unable to read from descriptor - %@",
                  [NSError _last]];
    }
  return d;
}

- (NSData*) readDataOfLength: (unsigned)len
{
  NSMutableData	*d;
  NSInteger     got;
  char buf[READ_SIZE];

  [self checkRead];
  if (isNonBlocking == YES)
    {
      [self setNonBlocking: NO];
    }

  d = [NSMutableData dataWithCapacity: len < READ_SIZE ? len : READ_SIZE];
  do
    {
      int	chunk = len > sizeof(buf) ? sizeof(buf) : len;

      got = [self read: buf length: chunk];
      if (got > 0)
	{
	  [d appendBytes: buf length: got];
	  len -= got;
	}
      else if (got < 0)
	{
	  [NSException raise: NSFileHandleOperationException
		      format: @"unable to read from descriptor - %@",
		      [NSError _last]];
	}
    }
  while (len > 0 && got > 0);

  return d;
}

- (void) writeData: (NSData*)item
{
  NSInteger   rval = 0;
  const void*	ptr = [item bytes];
  NSUInteger  len = [item length];
  NSUInteger  pos = 0;

  [self checkWrite];
  if (isNonBlocking == YES)
    {
      [self setNonBlocking: NO];
    }
  while (pos < len)
    {
      NSUInteger toWrite = len - pos;

      if (toWrite > NETBUF_SIZE)
	{
	  toWrite = NETBUF_SIZE;
	}
      rval = [self write: (char*)ptr+pos length: toWrite];
      if (rval < 0)
	{
	  if (errno == EAGAIN || errno == EINTR)
	    {
	      rval = 0;
	    }
	  else
	    {
	      break;
	    }
	}
      pos += rval;
    }
  if (rval < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"unable to write to descriptor - %@",
                  [NSError _last]];
    }
}


// Asynchronous I/O operations

- (void) acceptConnectionInBackgroundAndNotifyForModes: (NSArray*)modes
{
  [self checkAccept];
  readMax = 0;
  RELEASE(readInfo);
  readInfo = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [readInfo setObject: NSFileHandleConnectionAcceptedNotification
	       forKey: NotificationKey];
  [self watchReadDescriptorForModes: modes];
}

- (void) readDataInBackgroundAndNotifyLength: (NSUInteger)len
                                    forModes: (NSArray*)modes
{
  NSMutableData	*d;

  [self checkRead];
  if (len > 0x7fffffff)
    {
      [NSException raise: NSInvalidArgumentException
                  format: @"length (%u) too large", len];
    }
  readMax = len;
  RELEASE(readInfo);
  readInfo = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [readInfo setObject: NSFileHandleReadCompletionNotification
	       forKey: NotificationKey];
  d = [[NSMutableData alloc] initWithCapacity: readMax];
  [readInfo setObject: d forKey: NSFileHandleNotificationDataItem];
  RELEASE(d);
  [self watchReadDescriptorForModes: modes];
}

- (void) readInBackgroundAndNotifyForModes: (NSArray*)modes
{
  NSMutableData	*d;

  [self checkRead];
  readMax = -1;		// Accept any quantity of data.
  RELEASE(readInfo);
  readInfo = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [readInfo setObject: NSFileHandleReadCompletionNotification
	       forKey: NotificationKey];
  d = [[NSMutableData alloc] initWithCapacity: 0];
  [readInfo setObject: d forKey: NSFileHandleNotificationDataItem];
  RELEASE(d);
  [self watchReadDescriptorForModes: modes];
}

- (void) readToEndOfFileInBackgroundAndNotifyForModes: (NSArray*)modes
{
  NSMutableData	*d;

  [self checkRead];
  readMax = 0;
  RELEASE(readInfo);
  readInfo = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [readInfo setObject: NSFileHandleReadToEndOfFileCompletionNotification
	       forKey: NotificationKey];
  d = [[NSMutableData alloc] initWithCapacity: 0];
  [readInfo setObject: d forKey: NSFileHandleNotificationDataItem];
  RELEASE(d);
  [self watchReadDescriptorForModes: modes];
}

- (void) waitForDataInBackgroundAndNotifyForModes: (NSArray*)modes
{
  [self checkRead];
  readMax = 0;
  RELEASE(readInfo);
  readInfo = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [readInfo setObject: NSFileHandleDataAvailableNotification
	       forKey: NotificationKey];
  [readInfo setObject: [NSMutableData dataWithCapacity: 0]
	       forKey: NSFileHandleNotificationDataItem];
  [self watchReadDescriptorForModes: modes];
}

// Seeking within a file

- (unsigned long long) offsetInFile
{
  off_t	result = -1;

  if (isStandardFile && descriptor >= 0)
    {
#if	USE_ZLIB
      if (gzDescriptor != 0)
	{
	  result = gzseek(gzDescriptor, 0, SEEK_CUR);
	}
      else
#endif
      result = lseek(descriptor, 0, SEEK_CUR);
    }
  if (result < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"failed to move to offset in file - %@",
                  [NSError _last]];
    }
  return (unsigned long long)result;
}

- (unsigned long long) seekToEndOfFile
{
  off_t	result = -1;

  if (isStandardFile && descriptor >= 0)
    {
#if	USE_ZLIB
      if (gzDescriptor != 0)
	{
	  result = gzseek(gzDescriptor, 0, SEEK_END);
	}
      else
#endif
      result = lseek(descriptor, 0, SEEK_END);
    }
  if (result < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"failed to move to offset in file - %@",
                  [NSError _last]];
    }
  return (unsigned long long)result;
}

- (void) seekToFileOffset: (unsigned long long)pos
{
  off_t	result = -1;

  if (isStandardFile && descriptor >= 0)
    {
#if	USE_ZLIB
      if (gzDescriptor != 0)
	{
	  result = gzseek(gzDescriptor, (off_t)pos, SEEK_SET);
	}
      else
#endif
      result = lseek(descriptor, (off_t)pos, SEEK_SET);
    }
  if (result < 0)
    {
      [NSException raise: NSFileHandleOperationException
                  format: @"failed to move to offset in file - %@",
                  [NSError _last]];
    }
}


// Operations on file

- (void) closeFile
{
  if (descriptor < 0)
    {
      [NSException raise: NSFileHandleOperationException
		  format: @"attempt to close closed file"];
    }
  [self ignoreReadDescriptor];
  [self ignoreWriteDescriptor];

  [self setNonBlocking: wasNonBlocking];
#if	USE_ZLIB
  if (gzDescriptor != 0)
    {
      gzclose(gzDescriptor);
      gzDescriptor = 0;
    }
#endif
  (void)close(descriptor);
  descriptor = -1;
  acceptOK = NO;
  connectOK = NO;
  readOK = NO;
  writeOK = NO;

  /*
   *    Clear any pending operations on the file handle, sending
   *    notifications if necessary.
   */
  if (readInfo)
    {
      [readInfo setObject: @"File handle closed locally"
                   forKey: GSFileHandleNotificationError];
      [self postReadNotification];
    }

  if ([writeInfo count])
    {
      NSMutableDictionary       *info = [writeInfo objectAtIndex: 0];

      [info setObject: @"File handle closed locally"
               forKey: GSFileHandleNotificationError];
      [self postWriteNotification];
      [writeInfo removeAllObjects];
    }
}

- (void) synchronizeFile
{
  if (isStandardFile)
    {
      (void)sync();
    }
}

- (void) truncateFileAtOffset: (unsigned long long)pos
{
  if (isStandardFile && descriptor >= 0)
    {
      (void)ftruncate(descriptor, pos);
    }
  [self seekToFileOffset: pos];
}

- (void) writeInBackgroundAndNotify: (NSData*)item forModes: (NSArray*)modes
{
  NSMutableDictionary*	info;

  [self checkWrite];

  info = [[NSMutableDictionary alloc] initWithCapacity: 4];
  [info setObject: item forKey: NSFileHandleNotificationDataItem];
  [info setObject: GSFileHandleWriteCompletionNotification
		forKey: NotificationKey];
  if (modes != nil)
    {
      [info setObject: modes forKey: NSFileHandleNotificationMonitorModes];
    }
  [writeInfo addObject: info];
  RELEASE(info);
  [self watchWriteDescriptor];
}

- (void) writeInBackgroundAndNotify: (NSData*)item;
{
  [self writeInBackgroundAndNotify: item forModes: nil];
}

- (void) postReadNotification
{
  NSMutableDictionary	*info = readInfo;
  NSNotification	*n;
  NSNotificationQueue	*q;
  NSArray		*modes;
  NSString		*name;

  [self ignoreReadDescriptor];
  readInfo = nil;
  readMax = 0;
  modes = (NSArray*)[info objectForKey: NSFileHandleNotificationMonitorModes];
  name = (NSString*)[info objectForKey: NotificationKey];

  if (name == nil)
    {
      return;
    }
  n = [NSNotification notificationWithName: name object: self userInfo: info];

  RELEASE(info);	/* Retained by the notification.	*/

  q = [NSNotificationQueue defaultQueue];
  [q enqueueNotification: n
	    postingStyle: NSPostASAP
	    coalesceMask: NSNotificationNoCoalescing
		forModes: modes];
}

- (void) postWriteNotification
{
  NSMutableDictionary	*info = [writeInfo objectAtIndex: 0];
  NSNotificationQueue	*q;
  NSNotification	*n;
  NSArray		*modes;
  NSString		*name;

  [self ignoreWriteDescriptor];
  modes = (NSArray*)[info objectForKey: NSFileHandleNotificationMonitorModes];
  name = (NSString*)[info objectForKey: NotificationKey];

  n = [NSNotification notificationWithName: name object: self userInfo: info];

  writePos = 0;
  [writeInfo removeObjectAtIndex: 0];	/* Retained by notification.	*/

  q = [NSNotificationQueue defaultQueue];
  [q enqueueNotification: n
	    postingStyle: NSPostASAP
	    coalesceMask: NSNotificationNoCoalescing
		forModes: modes];
  if ((writeOK || connectOK) && [writeInfo count] > 0)
    {
      [self watchWriteDescriptor];	/* In case of queued writes.	*/
    }
}

- (BOOL) readInProgress
{
  if (readInfo)
    {
      return YES;
    }
  return NO;
}

- (BOOL) writeInProgress
{
  if ([writeInfo count] > 0)
    {
      return YES;
    }
  return NO;
}

- (void) ignoreReadDescriptor
{
  NSRunLoop	*l;
  NSArray	*modes;

  if (descriptor < 0)
    {
      return;
    }
  l = [NSRunLoop currentRunLoop];
  modes = nil;

  if (readInfo)
    {
      modes = (NSArray*)[readInfo objectForKey:
	NSFileHandleNotificationMonitorModes];
    }

  if (modes && [modes count])
    {
      unsigned int	i;

      for (i = 0; i < [modes count]; i++)
	{
	  [l removeEvent: (void*)(uintptr_t)descriptor
		    type: ET_RDESC
		 forMode: [modes objectAtIndex: i]
		     all: YES];
        }
    }
  else
    {
      [l removeEvent: (void*)(uintptr_t)descriptor
		type: ET_RDESC
	     forMode: NSDefaultRunLoopMode
		 all: YES];
    }
}

- (void) ignoreWriteDescriptor
{
  NSRunLoop	*l;
  NSArray	*modes;

  if (descriptor < 0)
    {
      return;
    }
  l = [NSRunLoop currentRunLoop];
  modes = nil;

  if ([writeInfo count] > 0)
    {
      NSMutableDictionary	*info = [writeInfo objectAtIndex: 0];

      modes = [info objectForKey: NSFileHandleNotificationMonitorModes];
    }

  if (modes && [modes count])
    {
      unsigned int	i;

      for (i = 0; i < [modes count]; i++)
	{
	  [l removeEvent: (void*)(uintptr_t)descriptor
		    type: ET_WDESC
		 forMode: [modes objectAtIndex: i]
		     all: YES];
        }
    }
  else
    {
      [l removeEvent: (void*)(uintptr_t)descriptor
		type: ET_WDESC
	     forMode: NSDefaultRunLoopMode
		 all: YES];
    }
}

- (void) watchReadDescriptorForModes: (NSArray*)modes;
{
  NSRunLoop	*l;

  if (descriptor < 0)
    {
      return;
    }

  l = [NSRunLoop currentRunLoop];
  [self setNonBlocking: YES];
  if (modes && [modes count])
    {
      unsigned int	i;

      for (i = 0; i < [modes count]; i++)
	{
	  [l addEvent: (void*)(uintptr_t)descriptor
		 type: ET_RDESC
	      watcher: self
	      forMode: [modes objectAtIndex: i]];
        }
      [readInfo setObject: modes forKey: NSFileHandleNotificationMonitorModes];
    }
  else
    {
      [l addEvent: (void*)(uintptr_t)descriptor
	     type: ET_RDESC
	  watcher: self
	  forMode: NSDefaultRunLoopMode];
    }
}

- (void) watchWriteDescriptor
{
  if (descriptor < 0)
    {
      return;
    }
  if ([writeInfo count] > 0)
    {
      NSMutableDictionary	*info = [writeInfo objectAtIndex: 0];
      NSRunLoop			*l = [NSRunLoop currentRunLoop];
      NSArray			*modes = nil;

      modes = [info objectForKey: NSFileHandleNotificationMonitorModes];

      [self setNonBlocking: YES];
      if (modes && [modes count])
	{
	  unsigned int	i;

	  for (i = 0; i < [modes count]; i++)
	    {
	      [l addEvent: (void*)(uintptr_t)descriptor
		     type: ET_WDESC
		  watcher: self
		  forMode: [modes objectAtIndex: i]];
	    }
	}
      else
	{
	  [l addEvent: (void*)(uintptr_t)descriptor
		 type: ET_WDESC
	      watcher: self
	      forMode: NSDefaultRunLoopMode];
	}
    }
}

- (void) receivedEventRead
{
  NSString	*operation;

  operation = [readInfo objectForKey: NotificationKey];
  if (operation == NSFileHandleConnectionAcceptedNotification)
    {
      struct sockaddr	buf;
      int			desc;
      unsigned int		blen = sizeof(buf);

      desc = accept(descriptor, &buf, &blen);
      if (desc == -1)
	{
	  NSString	*s;

	  s = [NSString stringWithFormat: @"Accept attempt failed - %@",
	    [NSError _last]];
	  [readInfo setObject: s forKey: GSFileHandleNotificationError];
	}
      else
	{ // Accept attempt completed.
	  GSFileHandle		*h;
	  struct sockaddr	sin;
	  unsigned int		size = sizeof(sin);
	  int			status;

	  /*
	   * Enable tcp-level tracking of whether connection is alive.
	   */
	  status = 1;
	  setsockopt(desc, SOL_SOCKET, SO_KEEPALIVE, (char *)&status,
	    sizeof(status));

	  h = [[[self class] alloc] initWithFileDescriptor: desc
						closeOnDealloc: YES];
	  h->isSocket = YES;
	  getpeername(desc, &sin, &size);
	  [h setAddr: &sin];
	  [readInfo setObject: h
		   forKey: NSFileHandleNotificationFileHandleItem];
	  RELEASE(h);
	}
      [self postReadNotification];
    }
  else if (operation == NSFileHandleDataAvailableNotification)
    {
      [self postReadNotification];
    }
  else
    {
      NSMutableData	*item;
      NSInteger     length;
      NSInteger     received = 0;
      char buf[READ_SIZE];

      item = [readInfo objectForKey: NSFileHandleNotificationDataItem];
      /*
       * We may have a maximum data size set...
       */
      if (readMax > 0)
        {
          length = (unsigned int)readMax - [item length];
          if (length > (int)sizeof(buf))
            {
	      length = sizeof(buf);
	    }
	}
      else
	{
	  length = sizeof(buf);
	}

      received = [self read: buf length: length];
      if (received == 0)
        { // Read up to end of file.
          [self postReadNotification];
        }
      else if (received < 0)
        {
          if (errno != EAGAIN && errno != EINTR)
            {
	      NSString	*s;

	      s = [NSString stringWithFormat: @"Read attempt failed - %@",
		[NSError _last]];
	      [readInfo setObject: s forKey: GSFileHandleNotificationError];
	      [self postReadNotification];
	    }
	}
      else
	{
	  [item appendBytes: buf length: received];
	  if (readMax < 0 || (readMax > 0 && (int)[item length] == readMax))
	    {
	      // Read a single chunk of data
	      [self postReadNotification];
	    }
	}
    }
}

- (void) receivedEventWrite
{
  NSString	*operation;
  NSMutableDictionary	*info;

  info = [writeInfo objectAtIndex: 0];
  operation = [info objectForKey: NotificationKey];
  if (operation == GSFileHandleConnectCompletionNotification
    || operation == SocksConnectNotification)
    { // Connection attempt completed.
      int	result;
      int	rval;
      unsigned	len = sizeof(result);

      rval = getsockopt(descriptor, SOL_SOCKET, SO_ERROR, (char*)&result, &len);
      if (rval != 0)
        {
          NSString	*s;

          s = [NSString stringWithFormat: @"Connect attempt failed - %@",
	    [NSError _last]];
          [info setObject: s forKey: GSFileHandleNotificationError];
	}
      else if (result != 0)
        {
          NSString	*s;

          s = [NSString stringWithFormat: @"Connect attempt failed - %@",
	    [NSError _systemError: result]];
          [info setObject: s forKey: GSFileHandleNotificationError];
        }
      else
        {
          readOK = YES;
          writeOK = YES;
        }
      connectOK = NO;
      [self postWriteNotification];
    }
  else
    {
      NSData      *item;
      NSInteger   length;
      const void  *ptr;

      item = [info objectForKey: NSFileHandleNotificationDataItem];
      length = [item length];
      ptr = [item bytes];
      if (writePos < length)
        {
          NSInteger	written;

          written = [self write: (char*)ptr+writePos
    		     length: length-writePos];
          if (written <= 0)
            {
	      if (written < 0 && errno != EAGAIN && errno != EINTR)
	        {
	          NSString	*s;

	          s = [NSString stringWithFormat:
		    @"Write attempt failed - %@", [NSError _last]];
	          [info setObject: s forKey: GSFileHandleNotificationError];
	          [self postWriteNotification];
	        }
	    }
	  else
            {
	      writePos += written;
	    }
	}
      if (writePos >= length)
        { // Write operation completed.
          [self postWriteNotification];
        }
    }
}

- (void) receivedEvent: (void*)data
                  type: (RunLoopEventType)type
		 extra: (void*)extra
	       forMode: (NSString*)mode
{
  NSDebugMLLog(@"NSFileHandle", @"%@ event: %d", self, type);

  if (isNonBlocking == NO)
    {
      [self setNonBlocking: YES];
    }
  if (type == ET_RDESC)
    {
      [self receivedEventRead];
    }
  else
    {
      [self receivedEventWrite];
    }
}

- (void) setAddr: (struct sockaddr *)sin
{
  NSString	*s;

  ASSIGN(address, GSPrivateSockaddrHost(sin));
  s = [NSString stringWithFormat: @"%d", GSPrivateSockaddrPort(sin)];
  ASSIGN(service, s);
  protocol = @"tcp";
}

- (void) setNonBlocking: (BOOL)flag
{
  if (descriptor < 0)
    {
      return;
    }
  else if (isStandardFile == YES)
    {
      return;
    }
  else if (isNonBlocking == flag)
    {
      return;
    }
  else
    {
      int	e;

      if ((e = fcntl(descriptor, F_GETFL, 0)) >= 0)
	{
	  if (flag == YES)
	    {
	      e |= NBLK_OPT;
	    }
	  else
	    {
	      e &= ~NBLK_OPT;
	    }
	  if (fcntl(descriptor, F_SETFL, e) < 0)
	    {
	      NSLog(@"unable to set non-blocking mode for %d - %@",
		descriptor, [NSError _last]);
	    }
	  else
	    {
	      isNonBlocking = flag;
	    }
	}
      else
	{
	  NSLog(@"unable to get non-blocking mode for %d - %@",
	    descriptor, [NSError _last]);
	}
    }
}

- (NSString*) socketAddress
{
  return address;
}

- (NSString*) socketLocalAddress
{
  NSString	*str = nil;
  struct sockaddr sin;
  unsigned	size = sizeof(sin);

  if (getsockname(descriptor, &sin, &size) == -1)
    {
      NSLog(@"unable to get socket name - %@", [NSError _last]);
    }
  else
    {
      str = GSPrivateSockaddrHost(&sin);
    }
  return str;
}

- (NSString*) socketLocalService
{
  NSString	*str = nil;
  struct sockaddr sin;
  unsigned	size = sizeof(sin);

  if (getsockname(descriptor, &sin, &size) == -1)
    {
      NSLog(@"unable to get socket name - %@", [NSError _last]);
    }
  else
    {
      str = [NSString stringWithFormat: @"%d", GSPrivateSockaddrPort(&sin)];
    }
  return str;
}

- (NSString*) socketProtocol
{
  return protocol;
}

- (NSString*) socketService
{
  return service;
}

- (BOOL) useCompression
{
#if	USE_ZLIB
  int	d;

  if (gzDescriptor != 0)
    {
      return YES;	// Already open
    }
  if (descriptor < 0)
    {
      return NO;	// No descriptor available.
    }
  if (readOK == YES && writeOK == YES)
    {
      return NO;	// Can't both read and write.
    }
  d = dup(descriptor);
  if (d < 0)
    {
      return NO;	// No descriptor available.
    }
  if (readOK == YES)
    {
      gzDescriptor = gzdopen(d, "rb");
    }
  else
    {
      gzDescriptor = gzdopen(d, "wb");
    }
  if (gzDescriptor == 0)
    {
      close(d);
      return NO;	// Open attempt failed.
    }
  return YES;
#endif
  return NO;
}
@end

