/** Implementation for GSSocketStream for GNUStep
   Copyright (C) 2006-2008 Free Software Foundation, Inc.

   Written by:  Derek Zhou <derekzhou@gmail.com>
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: 2006

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

#import "Foundation/NSArray.h"
#import "Foundation/NSByteOrder.h"
#import "Foundation/NSData.h"
#import "Foundation/NSDictionary.h"
#import "Foundation/NSEnumerator.h"
#import "Foundation/NSException.h"
#import "Foundation/NSHost.h"
#import "Foundation/NSLock.h"
#import "Foundation/NSNotification.h"
#import "Foundation/NSRunLoop.h"
#import "Foundation/NSUserDefaults.h"
#import "Foundation/NSValue.h"

#import "GSPrivate.h"
#import "GSStream.h"
#import "GSSocketStream.h"
#import "GSSocksParser/GSSocksParser.h"
#import "GNUstepBase/NSObject+GNUstepBase.h"

#import "GSTLS.h"

#ifndef SHUT_RD
# ifdef  SD_RECEIVE
#   define SHUT_RD      SD_RECEIVE
#   define SHUT_WR      SD_SEND
#   define SHUT_RDWR    SD_BOTH
# else
#   define SHUT_RD      0
#   define SHUT_WR      1
#   define SHUT_RDWR    2
# endif
#endif

#ifdef _WIN32
extern const char *inet_ntop(int, const void *, char *, size_t);
extern int inet_pton(int , const char *, void *);
#endif

unsigned
GSPrivateSockaddrLength(struct sockaddr *addr)
{
  switch (addr->sa_family) {
    case AF_INET:       return sizeof(struct sockaddr_in);
#ifdef AF_INET6
    case AF_INET6:      return sizeof(struct sockaddr_in6);
#endif
#ifndef	__MINGW__
    case AF_LOCAL:       return sizeof(struct sockaddr_un);
#endif
    default:            return 0;
  }
}

NSString *
GSPrivateSockaddrHost(struct sockaddr *addr)
{
  char		buf[40];

#if defined(AF_INET6)
  if (AF_INET6 == addr->sa_family)
    {
      struct sockaddr_in6	*addr6 = (struct sockaddr_in6*)(void*)addr;

      inet_ntop(AF_INET, &addr6->sin6_addr, buf, sizeof(buf));
      return [NSString stringWithUTF8String: buf];
    }
#endif
  inet_ntop(AF_INET, &((struct sockaddr_in*)(void*)addr)->sin_addr,
		  buf, sizeof(buf));
  return [NSString stringWithUTF8String: buf];
}

NSString *
GSPrivateSockaddrName(struct sockaddr *addr)
{
  return [NSString stringWithFormat: @"%@:%d",
    GSPrivateSockaddrHost(addr),
    GSPrivateSockaddrPort(addr)];
}

uint16_t
GSPrivateSockaddrPort(struct sockaddr *addr)
{
  uint16_t	port;

#if defined(AF_INET6)
  if (AF_INET6 == addr->sa_family)
    {
      struct sockaddr_in6	*addr6 = (struct sockaddr_in6*)(void*)addr;

      port = addr6->sin6_port;
      port = GSSwapBigI16ToHost(port);
      return port;
    }
#endif
  port = ((struct sockaddr_in*)(void*)addr)->sin_port;
  port = GSSwapBigI16ToHost(port);
  return port;
}

BOOL
GSPrivateSockaddrSetup(NSString *machine, uint16_t port,
  NSString *service, NSString *protocol, struct sockaddr *sin)
{
  memset(sin, '\0', sizeof(*sin));
  sin->sa_family = AF_INET;

  /* If we were given a hostname, we use any address for that host.
   * Otherwise we expect the given name to be an address unless it is
   * a null (any address).
   */
  if (0 != [machine length])
    {
      const char	*n;

      n = [machine UTF8String];
      if ((!isdigit(n[0]) || sscanf(n, "%*d.%*d.%*d.%*d") != 4)
	&& 0 == strchr(n, ':'))
	{
	  machine = [[NSHost hostWithName: machine] address];
	  n = [machine UTF8String];
	}

      if (0 == n)
	{
	  return NO;
	}
      if (0 == strchr(n, ':'))
	{
	  struct sockaddr_in	*addr = (struct sockaddr_in*)(void*)sin;

	  if (inet_pton(AF_INET, n, &addr->sin_addr) <= 0)
	    {
	      return NO;
	    }
	}
      else
	{
#if defined(AF_INET6)
	  struct sockaddr_in6	*addr6 = (struct sockaddr_in6*)(void*)sin;

	  sin->sa_family = AF_INET6;
	  if (inet_pton(AF_INET6, n, &addr6->sin6_addr) <= 0)
	    {
	      return NO;
	    }
#else
	  return NO;
#endif
	}
    }
  else
    {
      ((struct sockaddr_in*)(void*)sin)->sin_addr.s_addr
	= GSSwapHostI32ToBig(INADDR_ANY);
    }

  /* The optional service and protocol parameters may be used to
   * look up the port
   */
  if (nil != service)
    {
      const char	*sname;
      const char	*proto;
      struct servent	*sp;

      if (nil == protocol)
	{
	  proto = "tcp";
	}
      else
	{
	  proto = [protocol UTF8String];
	}

      sname = [service UTF8String];
      if ((sp = getservbyname(sname, proto)) == 0)
	{
	  const char*     ptr = sname;
	  int             val = atoi(ptr);

	  while (isdigit(*ptr))
	    {
	      ptr++;
	    }
	  if (*ptr == '\0' && val <= 0xffff)
	    {
	      port = val;
	    }
	  else if (strcmp(ptr, "gdomap") == 0)
	    {
#ifdef GDOMAP_PORT_OVERRIDE
	      port = GDOMAP_PORT_OVERRIDE;
#else
	      port = 538;	// IANA allocated port
#endif
	    }
	  else
	    {
	      return NO;
	    }
	}
      else
	{
	  port = GSSwapBigI16ToHost(sp->s_port);
	}
    }

#if defined(AF_INET6)
  if (AF_INET6 == sin->sa_family)
    {
      ((struct sockaddr_in6*)(void*)sin)->sin6_port = GSSwapHostI16ToBig(port);
    }
  else
    {
      ((struct sockaddr_in*)(void*)sin)->sin_port = GSSwapHostI16ToBig(port);
    }
#else
  ((struct sockaddr_ind*)sin)->sin6_port = GSSwapHostI16ToBig(port);
#endif
  return YES;
}

NS_INLINE void 
SetObjectForKey(NSMutableDictionary *dictionary, id object, id key)
{
    if (object) {
        [dictionary setObject:object forKey:key];
    }
}

NSDictionary *
GSPrivateParseGSSOCKS(NSString *gsSocks)
{
    if (!gsSocks && ![gsSocks length]) {
        return nil;
    }
    NSString *socksHost = gsSocks;
    NSString *socksPort = nil;
    NSString *socksUser = nil;
    NSString *socksPass = nil;
    
    NSRange range = [socksHost rangeOfString:@"@"];
    if (range.location != NSNotFound) {
        socksUser = [socksHost substringToIndex:range.location];
        socksHost = [socksHost substringFromIndex:NSMaxRange(range)];
        range = [socksUser rangeOfString:@":"];
        if (range.location != NSNotFound) {
            socksPass = [socksUser substringFromIndex:NSMaxRange(range)];
            socksUser = [socksUser substringToIndex:range.location];
        }
    }
    range = [socksHost rangeOfString:@":"];
    if (range.location != NSNotFound) {
        socksPort = [socksHost substringFromIndex:NSMaxRange(range)];
        socksHost = [socksHost substringToIndex:range.location];
    } else
        socksPort = @"1080";
    
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:5];
    SetObjectForKey(result, socksHost, NSStreamSOCKSProxyHostKey);
    SetObjectForKey(result, socksPort, NSStreamSOCKSProxyPortKey);
    SetObjectForKey(result, socksUser, NSStreamSOCKSProxyUserKey);
    SetObjectForKey(result, socksPass, NSStreamSOCKSProxyPasswordKey);
    SetObjectForKey(result, NSStreamSOCKSProxyVersion5, NSStreamSOCKSProxyVersionKey);
    return result;
}

NSDictionary *
GSPrivateGetGlobalSOCKSProxyConfiguration()
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *gsSocks = [defaults stringForKey:@"GSSOCKS"];
    if (!gsSocks) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        gsSocks = [environment objectForKey:@"SOCKS5_SERVER"];
        if (!gsSocks) {
            gsSocks = [environment objectForKey:@"SOCKS_SERVER"];
        }
    }
    return GSPrivateParseGSSOCKS(gsSocks);
}

/** The GSStreamHandler abstract class defines the methods used to
 * implement a handler object for a pair of streams.
 * The idea is that the handler is installed once the connection is
 * open, and a handshake is initiated.  During the handshake process
 * all stream events are sent to the handler rather than to the
 * stream delegate (the streams know to do this because the -handshake
 * method returns YES to tell them so).
 * While a handler is installed, the -read:maxLength: and -write:maxLength:
 * methods of the handle rare called instead of those of the streams (and
 * the handler may perform I/O using the streams by calling the private
 * -_read:maxLength: and _write:maxLength: methods instead of the public
 * methods).
 */
@interface GSStreamHandler : NSObject
{
  GSSocketInputStream   *istream;	// Not retained
  GSSocketOutputStream  *ostream;       // Not retained
  BOOL                  initialised;
  BOOL                  handshake;
  BOOL                  active;
}
+ (void) tryInput: (GSSocketInputStream*)i output: (GSSocketOutputStream*)o;
- (id) initWithInput: (GSSocketInputStream*)i
              output: (GSSocketOutputStream*)o;
- (GSSocketInputStream*) istream;
- (GSSocketOutputStream*) ostream;

- (void) bye;           /* Close down the handled session.   */
- (BOOL) handshake;     /* A handshake/hello is in progress. */
- (void) hello;         /* Start up the session handshake.   */
- (NSInteger) read: (uint8_t *)buffer maxLength: (NSUInteger)len;
- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)event;
- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len;
@end


@implementation GSStreamHandler

+ (void) initialize
{
  GSMakeWeakPointer(self, "istream");
  GSMakeWeakPointer(self, "ostream");
}

+ (void) tryInput: (GSSocketInputStream*)i output: (GSSocketOutputStream*)o
{
  [self subclassResponsibility: _cmd];
}

- (void) bye
{
  [self subclassResponsibility: _cmd];
}

- (BOOL) handshake
{
  return handshake;
}

- (void) hello
{
  [self subclassResponsibility: _cmd];
}

- (id) initWithInput: (GSSocketInputStream*)i
              output: (GSSocketOutputStream*)o
{
  istream = i;
  ostream = o;
  handshake = YES;
  return self;
}

- (GSSocketInputStream*) istream
{
  return istream;
}

- (GSSocketOutputStream*) ostream
{
  return ostream;
}

- (NSInteger) read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  [self subclassResponsibility: _cmd];
  return 0;
}

- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)event
{
  [self subclassResponsibility: _cmd];
}

- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  [self subclassResponsibility: _cmd];
  return 0;
}

@end

#if defined(HAVE_GNUTLS)

@interface GSTLSHandler : GSStreamHandler
{
@public
  GSTLSSession  *session;
}
@end

/* Callback to allow the TLS code to pull data from the remote system.
 * If the operation fails, this sets the error number.
 */
static ssize_t
GSTLSPull(gnutls_transport_ptr_t handle, void *buffer, size_t len)
{
  ssize_t       result;
  GSTLSHandler  *tls = (GSTLSHandler*)handle;

  result = [[tls istream] _read: buffer maxLength: len];
  if (result < 0)
    {
      NSInteger       e;

      if ([[tls istream] streamStatus] == NSStreamStatusError)
        {
          e = [[[(GSTLSHandler*)handle istream] streamError] code];
        }
      else
        {
          e = EAGAIN;	// Tell GNUTLS this would block.
        }
#if HAVE_GNUTLS_TRANSPORT_SET_ERRNO
      gnutls_transport_set_errno (tls->session->session, e);
#else
      errno = e;	// Not thread-safe
#endif
    }
  return result;
}

/* Callback to allow the TLS code to push data to the remote system.
 * If the operation fails, this sets the error number.
 */
static ssize_t
GSTLSPush(gnutls_transport_ptr_t handle, const void *buffer, size_t len)
{
  ssize_t       result;
  GSTLSHandler  *tls = (GSTLSHandler*)handle;

  result = [[tls ostream] _write: buffer maxLength: len];
  if (result < 0)
    {
      NSInteger       e;

      if ([[tls ostream] streamStatus] == NSStreamStatusError)
        {
          e = [[[tls ostream] streamError] code];
        }
      else
        {
          e = EAGAIN;	// Tell GNUTLS this would block.
        }
#if HAVE_GNUTLS_TRANSPORT_SET_ERRNO
      gnutls_transport_set_errno (tls->session->session, e);
#else
      errno = e;	// Not thread-safe
#endif

    }
  return result;
}

@implementation GSTLSHandler

static NSArray  *keys = nil;

+ (void) initialize
{
  [GSTLSObject class];
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
}

+ (void) tryInput: (GSSocketInputStream*)i output: (GSSocketOutputStream*)o
{
  NSString      *tls;

  tls = [i propertyForKey: NSStreamSocketSecurityLevelKey];
  if (tls == nil)
    {
      tls = [o propertyForKey: NSStreamSocketSecurityLevelKey];
      if (tls != nil)
        {
          [i setProperty: tls forKey: NSStreamSocketSecurityLevelKey];
        }
    }
  else
    {
      [o setProperty: tls forKey: NSStreamSocketSecurityLevelKey];
    }

  if (tls != nil)
    {
      GSTLSHandler      *h;

      h = [[GSTLSHandler alloc] initWithInput: i output: o];
      [i _setHandler: h];
      [o _setHandler: h];
      RELEASE(h);
    }
}

- (void) bye
{
  handshake = NO;
  active = NO;
  [session disconnect];
}

- (void) dealloc
{
  [self bye];
  DESTROY(session);
  [super dealloc];
}

- (BOOL) handshake
{
  return handshake;
}

- (void) hello
{
  if (active == NO)
    {
      if (handshake == NO)
        {
          /* Set flag to say we are now doing a handshake.
           */
          handshake = YES;
        }
      if ([session handshake] == YES)
        {
          handshake = NO;               // Handshake is now complete.
          active = [session active];    // The TLS session is now active.
        }
    }
}

- (id) initWithInput: (GSSocketInputStream*)i
              output: (GSSocketOutputStream*)o
{
  NSString              *str;
  NSMutableDictionary   *opts;
  NSUInteger            count;
  BOOL		        server;

  server = [[o propertyForKey: @"IsServer"] boolValue];

  str = [o propertyForKey: NSStreamSocketSecurityLevelKey];
  if (nil == str) str = [i propertyForKey: NSStreamSocketSecurityLevelKey];
  if ([str isEqual: NSStreamSocketSecurityLevelNone] == YES)
    {
      GSOnceMLog(@"NSStreamSocketSecurityLevelNone is insecure ..."
        @" not implemented");
      DESTROY(self);
      return nil;
    }
  else if ([str isEqual: NSStreamSocketSecurityLevelSSLv2] == YES)
    {
      GSOnceMLog(@"NSStreamSocketSecurityLevelTLSv2 is insecure ..."
        @" not implemented");
      DESTROY(self);
      return nil;
    }
  else if ([str isEqual: NSStreamSocketSecurityLevelSSLv3] == YES)
    {
      str = @"SSLv3";
    }
  else if ([str isEqual: NSStreamSocketSecurityLevelTLSv1] == YES)
    {
      str = @"TLSV1";
    }
  else
    {
      str = nil;
    }

  if ((self = [super initWithInput: i output: o]) == nil)
    {
      return nil;
    }

  /* Create the options dictionary, copying in any option from the stream
   * properties.  GSTLSPriority overrides NSStreamSocketSecurityLevelKey.
   */
  opts = [NSMutableDictionary new];
  if (nil != str) [opts setObject: str forKey: GSTLSPriority];
  count = [keys count];
  while (count-- > 0)
    {
      NSString  *key = [keys objectAtIndex: count];

      str = [o propertyForKey: key];
      if (nil == str) str = [i propertyForKey: key];
      if (nil != str) [opts setObject: str forKey: key];
    }
  
  session = [[GSTLSSession alloc] initWithOptions: opts
                                        direction: (server ? NO : YES)
                                        transport: (void*)self
                                             push: GSTLSPush
                                             pull: GSTLSPull];
  [opts release];
  initialised = YES;
  return self;
}

- (GSSocketInputStream*) istream
{
  return istream;
}

- (GSSocketOutputStream*) ostream
{
  return ostream;
}

- (NSInteger) read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  return [session read: buffer length: len];
}

- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)event
{
  NSDebugMLLog(@"NSStream",
    @"GSTLSHandler got %d on %p", event, stream);

  if (handshake == YES)
    {
      switch (event)
        {
          case NSStreamEventHasSpaceAvailable:
          case NSStreamEventHasBytesAvailable:
          case NSStreamEventOpenCompleted:
            [self hello]; /* try to complete the handshake */
            if (handshake == NO)
              {
                NSDebugMLLog(@"NSStream",
                  @"GSTLSHandler completed on %p", stream);
                if ([istream streamStatus] == NSStreamStatusOpen)
                  {
		    [istream _resetEvents: NSStreamEventOpenCompleted];
                    [istream _sendEvent: NSStreamEventOpenCompleted];
                  }
                else
                  {
		    [istream _resetEvents: NSStreamEventErrorOccurred];
                    [istream _sendEvent: NSStreamEventErrorOccurred];
                  }
                if ([ostream streamStatus]  == NSStreamStatusOpen)
                  {
		    [ostream _resetEvents: NSStreamEventOpenCompleted
		      | NSStreamEventHasSpaceAvailable];
                    [ostream _sendEvent: NSStreamEventOpenCompleted];
                    [ostream _sendEvent: NSStreamEventHasSpaceAvailable];
                  }
                else
                  {
		    [ostream _resetEvents: NSStreamEventErrorOccurred];
                    [ostream _sendEvent: NSStreamEventErrorOccurred];
                  }
              }
            break;
          default:
            break;
        }
    }
}

- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  return [session write: buffer length: len];
}

@end

#else /* HAVE_GNUTLS */

/*
 * GNUTLS not available ...
 */
@interface GSTLSHandler : GSStreamHandler
@end

@implementation GSTLSHandler
+ (void) tryInput: (GSSocketInputStream*)i output: (GSSocketOutputStream*)o
{
  NSString	*tls;

  tls = [i propertyForKey: NSStreamSocketSecurityLevelKey];
  if (tls == nil)
    {
      tls = [o propertyForKey: NSStreamSocketSecurityLevelKey];
    }
  if (tls != nil
    && [tls isEqualToString: NSStreamSocketSecurityLevelNone] == NO)
    {
      NSLog(@"Attempt to use SSL/TLS without support.");
      NSLog(@"Please reconfigure gnustep-base with GNU TLS.");
    }
  return;
}
- (id) initWithInput: (GSSocketInputStream*)i
              output: (GSSocketOutputStream*)o
{
  DESTROY(self);
  return nil;
}
@end

#endif /* HAVE_GNUTLS */


@interface GSSOCKS : GSStreamHandler<GSSocksParserDelegate> {
    GSSocksParser   *parser;
    NSData          *request;
    NSMutableData   *response;
    NSUInteger      bytesRequired;
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event;

@end

static NSDictionary *GlobalSOCKSProxyConfiguration = nil;

@implementation	GSSOCKS

+ (void)initialize
{
    GlobalSOCKSProxyConfiguration = [GSPrivateGetGlobalSOCKSProxyConfiguration() copy];
}

+ (void)tryInput:(GSSocketInputStream *)input output:(GSSocketOutputStream *)output
{
    NSDictionary *configuration;
    
    configuration = [input propertyForKey:NSStreamSOCKSProxyConfigurationKey];
    if (configuration == nil) {
        configuration = [output propertyForKey:NSStreamSOCKSProxyConfigurationKey];
        if (configuration != nil) {
            [input setProperty:configuration forKey:NSStreamSOCKSProxyConfigurationKey];
        }
    } else {
        [output setProperty:configuration forKey:NSStreamSOCKSProxyConfigurationKey];
    }
    
    if (configuration == nil) {
        if (GlobalSOCKSProxyConfiguration != nil) {
            configuration = GlobalSOCKSProxyConfiguration;
            [input setProperty:configuration forKey:NSStreamSOCKSProxyConfigurationKey];
            [output setProperty:configuration forKey:NSStreamSOCKSProxyConfigurationKey];
        } else {
            return;
        }
    }
    
    id handler = [[self alloc] initWithInput:input output:output];
    [input _setHandler:handler];
    [output _setHandler:handler];
    RELEASE(handler);
}

- (void)reconfigureStreamsForAddress:(NSString *)anAddress port:(NSUInteger)aPort
{
    anAddress = [[NSHost hostWithName:anAddress] address];
    NSInteger family = [anAddress rangeOfString:@":"].location == NSNotFound ? AF_INET : AF_INET6;
    [istream _setSocketAddress:anAddress port:aPort family:family];
    [ostream _setSocketAddress:anAddress port:aPort family:family];    
}

- (id)initWithInput:(GSSocketInputStream *)input
             output:(GSSocketOutputStream *)output
{
    if (!(self = [super initWithInput:input output:output])) {
        return nil;
    }
    if (![istream isKindOfClass:[GSInetInputStream class]] && ![istream isKindOfClass: [GSInet6InputStream class]]) {
        NSLog(@"Attempt to use SOCKS with non-INET stream will be ignored");
        DESTROY(self);
        return nil;
    }
    
    NSDictionary    *configuration = [istream propertyForKey:NSStreamSOCKSProxyConfigurationKey];
    struct sockaddr *socketAddress = [istream _address];
    
    NSString        *address;
    NSUInteger      port;
    /*
     * Record the host and port that the streams are supposed to be
     * connecting to.
     */
    address = GSPrivateSockaddrHost(socketAddress);
    port = GSPrivateSockaddrPort(socketAddress);
    
    parser = [[GSSocksParser alloc] initWithConfiguration:configuration
                                                  address:address
                                                     port:port];
    [parser setDelegate:self];
    request = nil;
    response = [[NSMutableData alloc] init];
    bytesRequired = 0;
    
    /*
     * Now reconfigure the streams so they will actually connect
     * to the socks proxy server.
     */
    address = [configuration objectForKey:NSStreamSOCKSProxyHostKey];
    port = [[configuration objectForKey:NSStreamSOCKSProxyPortKey] integerValue];
    [self reconfigureStreamsForAddress:address port:port];
    return self;
}

- (void)dealloc
{
    RELEASE(response);
    RELEASE(request);
    [parser setDelegate:nil];
    RELEASE(parser);
    [super dealloc];
}

- (void)hello
{
    if (handshake) {
        return;
    }
    handshake = YES;
    /*
     * Now send self an event to say we can write, to kick off the
     * handshake with the SOCKS server.
     */
    [self stream:ostream handleEvent:NSStreamEventHasSpaceAvailable];
}

- (void)bye
{
    if (!handshake)
    {
        return;
    }
    GSSocketInputStream     *input = RETAIN(istream);
    GSSocketOutputStream    *output = RETAIN(ostream);
    
    handshake = NO;
    
    [input _setHandler: nil];
    [output _setHandler: nil];
    [GSTLSHandler tryInput:input output:output];
    if ([input streamStatus] == NSStreamStatusOpen) {
        [input _resetEvents:NSStreamEventOpenCompleted];
        [input _sendEvent:NSStreamEventOpenCompleted];
    } else {
        [input _resetEvents:NSStreamEventErrorOccurred];
        [input _sendEvent:NSStreamEventErrorOccurred];
    }
    if ([output streamStatus] == NSStreamStatusOpen)
    {
        [output _resetEvents:NSStreamEventOpenCompleted | NSStreamEventHasSpaceAvailable];
        [output _sendEvent:NSStreamEventOpenCompleted];
        [output _sendEvent:NSStreamEventHasSpaceAvailable];
    } else {
        [output _resetEvents:NSStreamEventErrorOccurred];
        [output _sendEvent:NSStreamEventErrorOccurred];
    }
    RELEASE(input);
    RELEASE(output);
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
  return [istream _read:buffer maxLength:len];
}

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    return [ostream _write: buffer maxLength: len];
}

- (void)closeAndBye {
    [istream close];
    [ostream close];
    [self bye];
}

- (void)stream:(NSStream*)stream handleEvent:(NSStreamEvent)event
{
    if (!handshake) {
        return;
    }
    if (event == NSStreamEventErrorOccurred || [stream streamStatus] == NSStreamStatusError || [stream streamStatus] == NSStreamStatusClosed) {
        [self closeAndBye];
        return;
    }
    switch (event) {
        case NSStreamEventOpenCompleted:
        {
            if (stream == istream) {
                [parser start];
            }
            break;
        }
        case NSStreamEventHasSpaceAvailable:
        {
            NSUInteger requestLength = [request length];
            NSInteger bytesWritten = [self write:[request bytes] maxLength:requestLength];
            if (bytesWritten < 0) {
                [self closeAndBye];
                return;
            }
            NSData *requestTail = nil;
            if (bytesWritten < requestLength) {
                requestTail = [[NSData alloc] initWithBytes:[request bytes] + bytesWritten
                                                     length:requestLength - bytesWritten];
            }
            [request release];
            request = requestTail;
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            if (!bytesRequired) {
                break;
            }
            static NSUInteger const bufferSize = 1024;
            uint8_t buffer[bufferSize];
            NSUInteger length = MIN(bufferSize, bytesRequired);
            
            NSInteger bytesRead = [self read:buffer maxLength:length];
            if (bytesRead < 0) {
                [self closeAndBye];
                return;
            }
            [response appendBytes:buffer length:bytesRead];
            if (!(bytesRequired -= bytesRead)) {
                [parser parseNextChunk:response];
                [response setLength:0];
            }
            break;
        }
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
        {
            [self closeAndBye];
            return;
        }
        default:
            break;
    } 
}

- (void)parser:(GSSocksParser *)aParser encounteredError:(NSError *)anError
{
    [istream _recordError:anError];
    [self closeAndBye];
}

- (void)parser:(GSSocksParser *)aParser formedRequest:(NSData *)aRequest
{
    id previous = request;
    request = [aRequest retain];
    [previous release];
}

- (void)parser:(GSSocksParser *)aParser needsMoreBytes:(NSUInteger)aLength
{
    bytesRequired += aLength;
}

- (void)parser:(GSSocksParser *)aParser finishedWithAddress:(NSString *)anAddress port:(NSUInteger)aPort
{
    [self bye];
}

@end


static inline BOOL
socketError(int result)
{
#if defined(__MINGW__)
  return (result == SOCKET_ERROR) ? YES : NO;
#else
  return (result < 0) ? YES : NO;
#endif
}

static inline BOOL
socketWouldBlock()
{
  return GSWOULDBLOCK ? YES : NO;
}


static void
setNonBlocking(SOCKET fd)
{
#if defined(__MINGW__)
  unsigned long dummy = 1;

  if (ioctlsocket(fd, FIONBIO, &dummy) == SOCKET_ERROR)
    {
      NSLog(@"unable to set non-blocking mode - %@", [NSError _last]);
    }
#else
  int flags = fcntl(fd, F_GETFL, 0);

  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
    {
      NSLog(@"unable to set non-blocking mode - %@",
        [NSError _last]);
    }
#endif
}

@implementation GSSocketStream

- (void) dealloc
{
  if ([self _isOpened])
    {
      [self close];
    }
  [_sibling _setSibling: nil];
  _sibling = nil;
  DESTROY(_handler);
  [super dealloc];
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      // so that unopened access will fail
      _sibling = nil;
      _closing = NO;
      _passive = NO;
#if defined(__MINGW__)
      _loopID = WSA_INVALID_EVENT;
#else
      _loopID = (void*)(intptr_t)-1;
#endif
      _sock = INVALID_SOCKET;
      _handler = nil;
      _address.s.sa_family = AF_UNSPEC;
    }
  return self;
}

- (struct sockaddr*) _address
{
  return &_address.s;
}

- (id) propertyForKey: (NSString *)key
{
  id	result = [super propertyForKey: key];

  if (result == nil && _address.s.sa_family != AF_UNSPEC)
    {
      SOCKET    	s = [self _sock];
      struct sockaddr	sin;
      socklen_t	        size = sizeof(sin);

      if ([key isEqualToString: GSStreamLocalAddressKey])
	{
	  if (getsockname(s, (struct sockaddr*)&sin, &size) != -1)
	    {
	      result = GSPrivateSockaddrHost(&sin);
	    }
	}
      else if ([key isEqualToString: GSStreamLocalPortKey])
	{
	  if (getsockname(s, (struct sockaddr*)&sin, &size) != -1)
	    {
	      result = [NSString stringWithFormat: @"%d",
		(int)GSPrivateSockaddrPort(&sin)];
	    }
	}
      else if ([key isEqualToString: GSStreamRemoteAddressKey])
	{
	  if (getpeername(s, (struct sockaddr*)&sin, &size) != -1)
	    {
	      result = GSPrivateSockaddrHost(&sin);
	    }
	}
      else if ([key isEqualToString: GSStreamRemotePortKey])
	{
	  if (getpeername(s, (struct sockaddr*)&sin, &size) != -1)
	    {
	      result = [NSString stringWithFormat: @"%d",
		(int)GSPrivateSockaddrPort(&sin)];
	    }
	}
    }
  return result;
}

- (NSInteger) _read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  [self subclassResponsibility: _cmd];
  return -1;
}

- (void) _dispatchEvent:(NSNumber *)anEvent
{
    /* If the receiver has a TLS handshake in progress,
     * we must send events to the TLS handler rather than
     * the stream delegate.
     */
    if (_handler != nil && [_handler handshake] == YES)
    {
        id        del = _delegate;
        BOOL      val = _delegateValid;
        
        _delegate = _handler;
        _delegateValid = YES;
        [super _dispatchEvent: anEvent];
        _delegate = del;
        _delegateValid = val;
    }
    else
    {
        [super _dispatchEvent: anEvent];
    }
}

- (BOOL) _setSocketAddress: (NSString*)address
                      port: (NSInteger)port
                    family: (NSInteger)family
{
  uint16_t	p = (uint16_t)port;

  switch (family)
    {
      case AF_INET:
        {
          int           ptonReturn;
          const char    *addr_c;
          struct	sockaddr_in	peer;

          addr_c = [address cStringUsingEncoding: NSUTF8StringEncoding];
          memset(&peer, '\0', sizeof(peer));
          peer.sin_family = AF_INET;
          peer.sin_port = GSSwapHostI16ToBig(p);
          ptonReturn = inet_pton(AF_INET, addr_c, &peer.sin_addr);
          if (ptonReturn <= 0)   // error
            {
              return NO;
            }
          else
            {
              [self _setAddress: (struct sockaddr*)&peer];
              return YES;
            }
        }

#if defined(AF_INET6)
      case AF_INET6:
        {
          int           ptonReturn;
          const char    *addr_c;
          struct	sockaddr_in6	peer;

          addr_c = [address cStringUsingEncoding: NSUTF8StringEncoding];
          memset(&peer, '\0', sizeof(peer));
          peer.sin6_family = AF_INET6;
          peer.sin6_port = GSSwapHostI16ToBig(p);
          ptonReturn = inet_pton(AF_INET6, addr_c, &peer.sin6_addr);
          if (ptonReturn <= 0)   // error
            {
              return NO;
            }
          else
            {
              [self _setAddress: (struct sockaddr*)&peer];
              return YES;
            }
        }
#endif

#ifndef __MINGW__
      case AF_LOCAL:
	{
	  struct sockaddr_un	peer;
	  const char                *c_addr;

	  c_addr = [address fileSystemRepresentation];
	  memset(&peer, '\0', sizeof(peer));
	  peer.sun_family = AF_LOCAL;
	  if (strlen(c_addr) > sizeof(peer.sun_path)-1) // too long
	    {
	      return NO;
	    }
	  else
	    {
	      strncpy(peer.sun_path, c_addr, sizeof(peer.sun_path)-1);
	      [self _setAddress: (struct sockaddr*)&peer];
	      return YES;
	    }
	}
#endif

      default:
        return NO;
    }
}

- (void) _setAddress: (struct sockaddr*)address
{
  memcpy(&_address.s, address, GSPrivateSockaddrLength(address));
}

- (void) _setLoopID: (void *)ref
{
#if !defined(__MINGW__)
  _sock = (SOCKET)(intptr_t)ref;        // On gnu/linux _sock is _loopID
#endif
  _loopID = ref;
}

- (void) _setClosing: (BOOL)closing
{
  _closing = closing;
}

- (void) _setPassive: (BOOL)passive
{
  _passive = passive;
}

- (void) _setSibling: (GSSocketStream*)sibling
{
  _sibling = sibling;
}

- (void) _setSock: (SOCKET)sock
{
  setNonBlocking(sock);
  _sock = sock;

  /* As well as recording the socket, we set up the stream for monitoring it.
   * On unix style systems we set the socket descriptor as the _loopID to be
   * monitored, and on mswindows systems we create an event object to be
   * monitored (the socket events are assoociated with this object later).
   */
#if defined(__MINGW__)
  _loopID = CreateEvent(NULL, NO, NO, NULL);
#else
  _loopID = (void*)(intptr_t)sock;      // On gnu/linux _sock is _loopID
#endif
}

- (void) _setHandler: (id)h
{
  ASSIGN(_handler, h);
}

- (SOCKET) _sock
{
  return _sock;
}

- (NSInteger) _write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  [self subclassResponsibility: _cmd];
  return -1;
}

@end


@implementation GSSocketInputStream

+ (void) initialize
{
  GSMakeWeakPointer(self, "_sibling");
  if (self == [GSSocketInputStream class])
    {
      GSObjCAddClassBehavior(self, [GSSocketStream class]);
    }
}

- (void) open
{
  // could be opened because of sibling
  if ([self _isOpened])
    return;
  if (_passive || (_sibling && [_sibling _isOpened]))
    goto open_ok;
  // check sibling status, avoid double connect
  if (_sibling && [_sibling streamStatus] == NSStreamStatusOpening)
    {
      [self _setStatus: NSStreamStatusOpening];
      return;
    }
  else
    {
      int result;

      if ([self _sock] == INVALID_SOCKET)
        {
          SOCKET        s;

          if (_handler == nil)
            {
              [GSSOCKS tryInput: self output: _sibling];
            }
          s = socket(_address.s.sa_family, SOCK_STREAM, 0);
          if (BADSOCKET(s))
            {
              [self _recordError];
              return;
            }
          else
            {
              [self _setSock: s];
              [_sibling _setSock: s];
            }
        }

      if (_handler == nil)
        {
          [GSTLSHandler tryInput: self output: _sibling];
        }
      result = connect([self _sock], &_address.s,
        GSPrivateSockaddrLength(&_address.s));
      if (socketError(result))
        {
          if (!socketWouldBlock())
            {
              [self _recordError];
              [self _setHandler: nil];
              [_sibling _setHandler: nil];
              return;
            }
          /*
           * Need to set the status first, so that the run loop can tell
           * it needs to add the stream as waiting on writable, as an
           * indication of opened
           */
          [self _setStatus: NSStreamStatusOpening];
#if	defined(__MINGW__)
          WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
#endif
	  if (NSCountMapTable(_loops) > 0)
	    {
	      [self _schedule];
	      return;
	    }
          else
            {
              NSRunLoop *r;
              NSDate    *d;

              /* The stream was not scheduled in any run loop, so we
               * implement a blocking connect by running in the default
               * run loop mode.
               */
              r = [NSRunLoop currentRunLoop];
              d = [NSDate distantFuture];
              [r addStream: self mode: NSDefaultRunLoopMode];
              while ([r runMode: NSDefaultRunLoopMode beforeDate: d] == YES)
                {
                  if (_currentStatus != NSStreamStatusOpening)
                    {
                      break;
                    }
                }
              [r removeStream: self mode: NSDefaultRunLoopMode];
              return;
            }
        }
    }

 open_ok:
#if	defined(__MINGW__)
  WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
#endif
  [super open];
}

- (void) close
{
  if (_currentStatus == NSStreamStatusNotOpen)
    {
      NSDebugMLLog(@"NSStream",
        @"Attempt to close unopened stream %@", self);
      return;
    }
  if (_currentStatus == NSStreamStatusClosed)
    {
      NSDebugMLLog(@"NSStream",
        @"Attempt to close already closed stream %@", self);
      return;
    }
  [_handler bye];
#if	defined(__MINGW__)
  if (_sibling && [_sibling streamStatus] != NSStreamStatusClosed)
    {
      /*
       * Windows only permits a single event to be associated with a socket
       * at any time, but the runloop system only allows an event handle to
       * be added to the loop once, and we have two streams for each socket.
       * So we use two events, one for each stream, and when one stream is
       * closed, we must call WSAEventSelect to ensure that the event handle
       * of the sibling is used to signal events from now on.
       */
      WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
      shutdown(_sock, SHUT_RD);
      WSAEventSelect(_sock, [_sibling _loopID], FD_ALL_EVENTS);
    }
  else
    {
      closesocket(_sock);
    }
  WSACloseEvent(_loopID);
  [super close];
  _loopID = WSA_INVALID_EVENT;
#else
  // read shutdown is ignored, because the other side may shutdown first.
  if (!_sibling || [_sibling streamStatus] == NSStreamStatusClosed)
    close((int)_loopID);
  else
    shutdown((int)_loopID, SHUT_RD);
  [super close];
  _loopID = (void*)(intptr_t)-1;
#endif
  _sock = INVALID_SOCKET;
}

- (NSInteger) read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer for buffer"];
    }
  if (len == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"zero byte read requested"];
    }

  if (_handler == nil)
    return [self _read: buffer maxLength: len];
  else
    return [_handler read: buffer maxLength: len];
}

- (NSInteger) _read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  NSInteger readLen;

  _events &= ~NSStreamEventHasBytesAvailable;

  if ([self streamStatus] == NSStreamStatusClosed)
    {
      return 0;
    }
  if ([self streamStatus] == NSStreamStatusAtEnd)
    {
      readLen = 0;
    }
  else
    {
#if	defined(__MINGW__)
      readLen = recv([self _sock], (char*) buffer, (socklen_t) len, 0);
#else
      readLen = read([self _sock], buffer, len);
#endif
    }
  if (socketError((int)readLen))
    {
      if (_closing == YES)
        {
          /* If a read fails on a closing socket,
           * we have reached the end of all data sent by
           * the remote end before it shut down.
           */
          [self _setClosing: NO];
          [self _setStatus: NSStreamStatusAtEnd];
          [self _sendEvent: NSStreamEventEndEncountered];
          readLen = 0;
        }
      else
        {
          if (socketWouldBlock())
            {
              /* We need an event from the operating system
               * to tell us we can start reading again.
               */
              [self _setStatus: NSStreamStatusReading];
            }
          else
            {
              [self _recordError];
            }
          readLen = -1;
        }
    }
  else if (readLen == 0)
    {
      [self _setStatus: NSStreamStatusAtEnd];
      [self _sendEvent: NSStreamEventEndEncountered];
    }
  else
    {
      [self _setStatus: NSStreamStatusOpen];
    }
  return readLen;
}

- (BOOL) getBuffer: (uint8_t **)buffer length: (NSUInteger *)len
{
  return NO;
}

- (void) _dispatch
{
#if	defined(__MINGW__)
  AUTORELEASE(RETAIN(self));
  /*
   * Windows only permits a single event to be associated with a socket
   * at any time, but the runloop system only allows an event handle to
   * be added to the loop once, and we have two streams for each socket.
   * So we use two events, one for each stream, and the _dispatch method
   * must handle things for both streams.
   */
  if ([self streamStatus] == NSStreamStatusClosed)
    {
      /*
       * It is possible the stream is closed yet recieving event because
       * of not closed sibling
       */
      NSAssert([_sibling streamStatus] != NSStreamStatusClosed,
	@"Received event for closed stream");
      [_sibling _dispatch];
    }
  else
    {
      WSANETWORKEVENTS events;
      int error = 0;
      int getReturn = -1;

      if (WSAEnumNetworkEvents(_sock, _loopID, &events) == SOCKET_ERROR)
	{
	  error = WSAGetLastError();
	}
// else NSLog(@"EVENTS 0x%x on %p", events.lNetworkEvents, self);

      if ([self streamStatus] == NSStreamStatusOpening)
	{
	  [self _unschedule];
	  if (error == 0)
	    {
	      socklen_t len = sizeof(error);

	      getReturn = getsockopt(_sock, SOL_SOCKET, SO_ERROR,
		(char*)&error, &len);
	    }

	  if (getReturn >= 0 && error == 0
	    && (events.lNetworkEvents & FD_CONNECT))
	    { // finish up the opening
	      _passive = YES;
	      [self open];
	      // notify sibling
	      if (_sibling)
		{
		  [_sibling open];
		  [_sibling _sendEvent: NSStreamEventOpenCompleted];
		}
	      [self _sendEvent: NSStreamEventOpenCompleted];
	    }
	}

      if (error != 0)
	{
	  errno = error;
	  [self _recordError];
	  [_sibling _recordError];
	  [self _sendEvent: NSStreamEventErrorOccurred];
	  [_sibling _sendEvent: NSStreamEventErrorOccurred];
	}
      else
	{
	  if (events.lNetworkEvents & FD_WRITE)
	    {
	      NSAssert([_sibling _isOpened], NSInternalInconsistencyException);
	      /* Clear NSStreamStatusWriting if it was set */
	      [_sibling _setStatus: NSStreamStatusOpen];
	    }

	  /* On winsock a socket is always writable unless it has had
	   * failure/closure or a write blocked and we have not been
	   * signalled again.
	   */
	  while ([_sibling _unhandledData] == NO
	    && [_sibling hasSpaceAvailable])
	    {
	      [_sibling _sendEvent: NSStreamEventHasSpaceAvailable];
	    }

	  if (events.lNetworkEvents & FD_READ)
	    {
	      [self _setStatus: NSStreamStatusOpen];
	      while ([self hasBytesAvailable]
		&& [self _unhandledData] == NO)
		{
	          [self _sendEvent: NSStreamEventHasBytesAvailable];
		}
	    }

	  if (events.lNetworkEvents & FD_CLOSE)
	    {
	      [self _setClosing: YES];
	      [_sibling _setClosing: YES];
	      while ([self hasBytesAvailable]
		&& [self _unhandledData] == NO)
		{
		  [self _sendEvent: NSStreamEventHasBytesAvailable];
		}
	    }
	  if (events.lNetworkEvents == 0)
	    {
	      [self _sendEvent: NSStreamEventHasBytesAvailable];
	    }
	}
    }
#else /* __MINGW__ */    
  NSStreamEvent myEvent;

  if ([self streamStatus] == NSStreamStatusOpening)
    {
      int error;
      int result;
      socklen_t len = sizeof(error);

      IF_NO_GC([[self retain] autorelease];)
      [self _unschedule];
      result = getsockopt([self _sock], SOL_SOCKET, SO_ERROR, &error, &len);

      if (result >= 0 && !error)
        { // finish up the opening
          myEvent = NSStreamEventOpenCompleted;
          _passive = YES;
          [self open];
          // notify sibling
          [_sibling open];
          [_sibling _sendEvent: myEvent];
        }
      else // must be an error
        {
          if (error)
            errno = error;
          [self _recordError];
          myEvent = NSStreamEventErrorOccurred;
          [_sibling _recordError];
          [_sibling _sendEvent: myEvent];
        }
    }
  else if ([self streamStatus] == NSStreamStatusAtEnd)
    {
      myEvent = NSStreamEventEndEncountered;
    }
  else
    {
      [self _setStatus: NSStreamStatusOpen];
      myEvent = NSStreamEventHasBytesAvailable;
    }
  [self _sendEvent: myEvent];
#endif
}

#if	defined(__MINGW__)
- (BOOL) runLoopShouldBlock: (BOOL*)trigger
{
  *trigger = YES;
  return YES;
}
#endif

@end


@implementation GSSocketOutputStream

+ (void) initialize
{
  GSMakeWeakPointer(self, "_sibling");
  if (self == [GSSocketOutputStream class])
    {
      GSObjCAddClassBehavior(self, [GSSocketStream class]);
    }
}

- (NSInteger) _write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  NSInteger writeLen;

  _events &= ~NSStreamEventHasSpaceAvailable;

  if ([self streamStatus] == NSStreamStatusClosed)
    {
      return 0;
    }
  if ([self streamStatus] == NSStreamStatusAtEnd)
    {
      [self _sendEvent: NSStreamEventEndEncountered];
      return 0;
    }

#if	defined(__MINGW__)
  writeLen = send([self _sock], (char*) buffer, (socklen_t) len, 0);
#else
  writeLen = write([self _sock], buffer, (socklen_t) len);
#endif

  if (socketError((int)writeLen))
    {
      if (_closing == YES)
        {
          /* If a write fails on a closing socket,
           * we know the other end is no longer reading.
           */
          [self _setClosing: NO];
          [self _setStatus: NSStreamStatusAtEnd];
          [self _sendEvent: NSStreamEventEndEncountered];
          writeLen = 0;
        }
      else
        {
          if (socketWouldBlock())
            {
              /* We need an event from the operating system
               * to tell us we can start writing again.
               */
              [self _setStatus: NSStreamStatusWriting];
            }
          else
            {
              [self _recordError];
            }
          writeLen = -1;
        }
    }
  else
    {
      [self _setStatus: NSStreamStatusOpen];
    }
  return writeLen;
}

- (void) open
{
  // could be opened because of sibling
  if ([self _isOpened])
    return;
  if (_passive || (_sibling && [_sibling _isOpened]))
    goto open_ok;
  // check sibling status, avoid double connect
  if (_sibling && [_sibling streamStatus] == NSStreamStatusOpening)
    {
      [self _setStatus: NSStreamStatusOpening];
      return;
    }
  else
    {
      int result;

      if ([self _sock] == INVALID_SOCKET)
        {
          SOCKET        s;

          if (_handler == nil)
            {
              [GSSOCKS tryInput: _sibling output: self];
            }
          s = socket(_address.s.sa_family, SOCK_STREAM, 0);
          if (BADSOCKET(s))
            {
              [self _recordError];
              return;
            }
          else
            {
              [self _setSock: s];
              [_sibling _setSock: s];
            }
        }

      if (_handler == nil)
        {
          [GSTLSHandler tryInput: _sibling output: self];
        }

      result = connect([self _sock], &_address.s,
        GSPrivateSockaddrLength(&_address.s));
      if (socketError(result))
        {
          if (!socketWouldBlock())
            {
              [self _recordError];
              [self _setHandler: nil];
              [_sibling _setHandler: nil];
              return;
            }
          /*
           * Need to set the status first, so that the run loop can tell
           * it needs to add the stream as waiting on writable, as an
           * indication of opened
           */
          [self _setStatus: NSStreamStatusOpening];
#if	defined(__MINGW__)
          WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
#endif
	  if (NSCountMapTable(_loops) > 0)
	    {
	      [self _schedule];
	      return;
	    }
          else
            {
              NSRunLoop *r;
              NSDate    *d;

              /* The stream was not scheduled in any run loop, so we
               * implement a blocking connect by running in the default
               * run loop mode.
               */
              r = [NSRunLoop currentRunLoop];
              d = [NSDate distantFuture];
              [r addStream: self mode: NSDefaultRunLoopMode];
              while ([r runMode: NSDefaultRunLoopMode beforeDate: d] == YES)
                {
                  if (_currentStatus != NSStreamStatusOpening)
                    {
                      break;
                    }
                }
              [r removeStream: self mode: NSDefaultRunLoopMode];
              return;
            }
        }
    }

 open_ok:
#if	defined(__MINGW__)
  WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
#endif
  [super open];

}


- (void) close
{
  if (_currentStatus == NSStreamStatusNotOpen)
    {
      NSDebugMLLog(@"NSStream",
        @"Attempt to close unopened stream %@", self);
      return;
    }
  if (_currentStatus == NSStreamStatusClosed)
    {
      NSDebugMLLog(@"NSStream",
        @"Attempt to close already closed stream %@", self);
      return;
    }
  [_handler bye];
#if	defined(__MINGW__)
  if (_sibling && [_sibling streamStatus] != NSStreamStatusClosed)
    {
      /*
       * Windows only permits a single event to be associated with a socket
       * at any time, but the runloop system only allows an event handle to
       * be added to the loop once, and we have two streams for each socket.
       * So we use two events, one for each stream, and when one stream is
       * closed, we must call WSAEventSelect to ensure that the event handle
       * of the sibling is used to signal events from now on.
       */
      WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
      shutdown(_sock, SHUT_WR);
      WSAEventSelect(_sock, [_sibling _loopID], FD_ALL_EVENTS);
    }
  else
    {
      closesocket(_sock);
    }
  WSACloseEvent(_loopID);
  [super close];
  _loopID = WSA_INVALID_EVENT;
#else
  // read shutdown is ignored, because the other side may shutdown first.
  if (!_sibling || [_sibling streamStatus] == NSStreamStatusClosed)
    close((int)_loopID);
  else
    shutdown((int)_loopID, SHUT_WR);
  [super close];
  _loopID = (void*)(intptr_t)-1;
#endif
  _sock = INVALID_SOCKET;
}

- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer for buffer"];
    }
  if (len == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"zero byte length write requested"];
    }

  if (_handler == nil)
    return [self _write: buffer maxLength: len];
  else
    return [_handler write: buffer maxLength: len];
}

- (void) _dispatch
{
#if	defined(__MINGW__)
  AUTORELEASE(RETAIN(self));
  /*
   * Windows only permits a single event to be associated with a socket
   * at any time, but the runloop system only allows an event handle to
   * be added to the loop once, and we have two streams for each socket.
   * So we use two events, one for each stream, and the _dispatch method
   * must handle things for both streams.
   */
  if ([self streamStatus] == NSStreamStatusClosed)
    {
      /*
       * It is possible the stream is closed yet recieving event because
       * of not closed sibling
       */
      NSAssert([_sibling streamStatus] != NSStreamStatusClosed,
	@"Received event for closed stream");
      [_sibling _dispatch];
    }
  else
    {
      WSANETWORKEVENTS events;
      int error = 0;
      int getReturn = -1;

      if (WSAEnumNetworkEvents(_sock, _loopID, &events) == SOCKET_ERROR)
	{
	  error = WSAGetLastError();
	}
// else NSLog(@"EVENTS 0x%x on %p", events.lNetworkEvents, self);

      if ([self streamStatus] == NSStreamStatusOpening)
	{
	  [self _unschedule];
	  if (error == 0)
	    {
	      socklen_t len = sizeof(error);

	      getReturn = getsockopt(_sock, SOL_SOCKET, SO_ERROR,
		(char*)&error, &len);
	    }

	  if (getReturn >= 0 && error == 0
	    && (events.lNetworkEvents & FD_CONNECT))
	    { // finish up the opening
	      events.lNetworkEvents ^= FD_CONNECT;
	      _passive = YES;
	      [self open];
	      // notify sibling
	      if (_sibling)
		{
		  [_sibling open];
		  [_sibling _sendEvent: NSStreamEventOpenCompleted];
		}
	      [self _sendEvent: NSStreamEventOpenCompleted];
	    }
	}

      if (error != 0)
	{
	  errno = error;
	  [self _recordError];
	  [_sibling _recordError];
	  [self _sendEvent: NSStreamEventErrorOccurred];
	  [_sibling _sendEvent: NSStreamEventErrorOccurred];
	}
      else
	{
	  if (events.lNetworkEvents & FD_WRITE)
	    {
	      /* Clear NSStreamStatusWriting if it was set */
	      [self _setStatus: NSStreamStatusOpen];
	    }

	  /* On winsock a socket is always writable unless it has had
	   * failure/closure or a write blocked and we have not been
	   * signalled again.
	   */
	  while ([self _unhandledData] == NO && [self hasSpaceAvailable])
	    {
	      [self _sendEvent: NSStreamEventHasSpaceAvailable];
	    }

	  if (events.lNetworkEvents & FD_READ)
	    {
	      [_sibling _setStatus: NSStreamStatusOpen];
	      while ([_sibling hasBytesAvailable]
		&& [_sibling _unhandledData] == NO)
		{
	          [_sibling _sendEvent: NSStreamEventHasBytesAvailable];
		}
	    }
	  if (events.lNetworkEvents & FD_CLOSE)
	    {
	      [self _setClosing: YES];
	      [_sibling _setClosing: YES];
	      while ([_sibling hasBytesAvailable]
		&& [_sibling _unhandledData] == NO)
		{
		  [_sibling _sendEvent: NSStreamEventHasBytesAvailable];
		}
	    }
	  if (events.lNetworkEvents == 0)
	    {
	      [self _sendEvent: NSStreamEventHasSpaceAvailable];
	    }
	}
    }
#else /* __MINGW__ */
  NSStreamEvent myEvent;

  if ([self streamStatus] == NSStreamStatusOpening)
    {
      int error;
      socklen_t len = sizeof(error);
      int result;

      IF_NO_GC([[self retain] autorelease];)
      [self _schedule];
      result
	= getsockopt((int)_loopID, SOL_SOCKET, SO_ERROR, &error, &len);
      if (result >= 0 && !error)
        { // finish up the opening
          myEvent = NSStreamEventOpenCompleted;
          _passive = YES;
          [self open];
          // notify sibling
          [_sibling open];
          [_sibling _sendEvent: myEvent];
        }
      else // must be an error
        {
          if (error)
            errno = error;
          [self _recordError];
          myEvent = NSStreamEventErrorOccurred;
          [_sibling _recordError];
          [_sibling _sendEvent: myEvent];
        }
    }
  else if ([self streamStatus] == NSStreamStatusAtEnd)
    {
      myEvent = NSStreamEventEndEncountered;
    }
  else
    {
      [self _setStatus: NSStreamStatusOpen];
      myEvent = NSStreamEventHasSpaceAvailable;
    }
  [self _sendEvent: myEvent];
#endif
}

#if	defined(__MINGW__)
- (BOOL) runLoopShouldBlock: (BOOL*)trigger
{
  *trigger = YES;
  if ([self _unhandledData] == YES && [self streamStatus] == NSStreamStatusOpen)
    {
      /* In winsock, a writable status is only signalled if an earlier
       * write failed (because it would block), so we must simulate the
       * writable event by having the run loop trigger without blocking.
       */
      return NO;
    }
  return YES;
}
#endif

@end

@implementation GSSocketServerStream

+ (void) initialize
{
  GSMakeWeakPointer(self, "_sibling");
  if (self == [GSSocketServerStream class])
    {
      GSObjCAddClassBehavior(self, [GSSocketStream class]);
    }
}

- (Class) _inputStreamClass
{
  [self subclassResponsibility: _cmd];
  return Nil;
}

- (Class) _outputStreamClass
{
  [self subclassResponsibility: _cmd];
  return Nil;
}

- (void) open
{
  int bindReturn;
  int listenReturn;
  SOCKET s;

  if (_currentStatus != NSStreamStatusNotOpen)
    {
      NSDebugMLLog(@"NSStream",
        @"Attempt to re-open stream %@", self);
      return;
    }

  s = socket(_address.s.sa_family, SOCK_STREAM, 0);
  if (BADSOCKET(s))
    {
      [self _recordError];
      [self _sendEvent: NSStreamEventErrorOccurred];
      return;
    }
  else
    {
      [(GSSocketStream*)self _setSock: s];
    }

#ifndef	BROKEN_SO_REUSEADDR
  if (_address.s.sa_family == AF_INET
#ifdef  AF_INET6
    || _address.s.sa_family == AF_INET6
#endif
  )
    {
      /*
       * Under decent systems, SO_REUSEADDR means that the port can be reused
       * immediately that this process exits.  Under some it means
       * that multiple processes can serve the same port simultaneously.
       * We don't want that broken behavior!
       */
      int	status = 1;

      setsockopt([self _sock], SOL_SOCKET, SO_REUSEADDR,
        (char *)&status, sizeof(status));
    }
#endif

  bindReturn = bind([self _sock],
    &_address.s, GSPrivateSockaddrLength(&_address.s));
  if (socketError(bindReturn))
    {
      [self _recordError];
      [self _sendEvent: NSStreamEventErrorOccurred];
      return;
    }
  listenReturn = listen([self _sock], GSBACKLOG);
  if (socketError(listenReturn))
    {
      [self _recordError];
      [self _sendEvent: NSStreamEventErrorOccurred];
      return;
    }
#if	defined(__MINGW__)
  WSAEventSelect(_sock, _loopID, FD_ALL_EVENTS);
#endif
  [super open];
}

- (void) close
{
#if	defined(__MINGW__)
  if (_loopID != WSA_INVALID_EVENT)
    {
      WSACloseEvent(_loopID);
    }
  if (_sock != INVALID_SOCKET)
    {
      closesocket(_sock);
      [super close];
      _loopID = WSA_INVALID_EVENT;
    }
#else
  if (_loopID != (void*)(intptr_t)-1)
    {
      close((int)_loopID);
      [super close];
      _loopID = (void*)(intptr_t)-1;
    }
#endif
  _sock = INVALID_SOCKET;
}

- (void) acceptWithInputStream: (NSInputStream **)inputStream
                  outputStream: (NSOutputStream **)outputStream
{
  GSSocketStream *ins = AUTORELEASE([[self _inputStreamClass] new]);
  GSSocketStream *outs = AUTORELEASE([[self _outputStreamClass] new]);
  /* Align on a 2 byte boundary for a 16bit port number in the sockaddr
   */
  struct {
    uint8_t bytes[BUFSIZ];
  } __attribute__((aligned(2)))buf;
  struct sockaddr       *addr = (struct sockaddr*)&buf;
  socklen_t		len = sizeof(buf);
  int			acceptReturn;

  acceptReturn = accept([self _sock], addr, &len);
  _events &= ~NSStreamEventHasBytesAvailable;
  if (socketError(acceptReturn))
    { // test for real error
      if (!socketWouldBlock())
	{
          [self _recordError];
	}
      ins = nil;
      outs = nil;
    }
  else
    {
      // no need to connect again
      [ins _setPassive: YES];
      [outs _setPassive: YES];
      // copy the addr to outs
      [ins _setAddress: addr];
      [outs _setAddress: addr];
      [ins _setSock: acceptReturn];
      [outs _setSock: acceptReturn];
      [ins setProperty: @"YES" forKey: @"IsServer"];
    }
  if (inputStream)
    {
      [ins _setSibling: outs];
      *inputStream = (NSInputStream*)ins;
    }
  if (outputStream)
    {
      [outs _setSibling: ins];
      *outputStream = (NSOutputStream*)outs;
    }
}

- (void) _dispatch
{
#if	defined(__MINGW__)
  WSANETWORKEVENTS events;

  if (WSAEnumNetworkEvents(_sock, _loopID, &events) == SOCKET_ERROR)
    {
      errno = WSAGetLastError();
      [self _recordError];
      [self _sendEvent: NSStreamEventErrorOccurred];
    }
  else if (events.lNetworkEvents & FD_ACCEPT)
    {
      events.lNetworkEvents ^= FD_ACCEPT;
      [self _setStatus: NSStreamStatusReading];
      [self _sendEvent: NSStreamEventHasBytesAvailable];
    }
#else
  NSStreamEvent myEvent;

  [self _setStatus: NSStreamStatusOpen];
  myEvent = NSStreamEventHasBytesAvailable;
  [self _sendEvent: myEvent];
#endif
}

@end



@implementation GSInetInputStream

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]) != nil)
    {
      if ([self _setSocketAddress: addr port: port family: AF_INET] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}

@end

@implementation GSInet6InputStream
#if	defined(AF_INET6)

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]) != nil)
    {
      if ([self _setSocketAddress: addr port: port family: AF_INET6] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}

#else
- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  DESTROY(self);
  return nil;
}
#endif
@end

@implementation GSInetOutputStream

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]) != nil)
    {
      if ([self _setSocketAddress: addr port: port family: AF_INET] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}

@end

@implementation GSInet6OutputStream
#if	defined(AF_INET6)

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]) != nil)
    {
      if ([self _setSocketAddress: addr port: port family: AF_INET6] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}

#else
- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  DESTROY(self);
  return nil;
}
#endif
@end

@implementation GSInetServerStream

- (Class) _inputStreamClass
{
  return [GSInetInputStream class];
}

- (Class) _outputStreamClass
{
  return [GSInetOutputStream class];
}

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]) != nil)
    {
      if ([addr length] == 0)
        {
          addr = @"0.0.0.0";
        }
      if ([self _setSocketAddress: addr port: port family: AF_INET] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}

@end

@implementation GSInet6ServerStream
#if	defined(AF_INET6)
- (Class) _inputStreamClass
{
  return [GSInet6InputStream class];
}

- (Class) _outputStreamClass
{
  return [GSInet6OutputStream class];
}

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  if ((self = [super init]))
    {
      if ([addr length] == 0)
        {
          addr = @"0:0:0:0:0:0:0:0";   /* Bind on all addresses */
        }
      if ([self _setSocketAddress: addr port: port family: AF_INET6] == NO)
        {
          DESTROY(self);
        }
    }
  return self;
}
#else
- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  DESTROY(self);
  return nil;
}
#endif
@end

