#import "GSSocksParser.h"
#import "GSSocks4Parser.h"
#import "GSSocks5Parser.h"
#import <Foundation/NSException.h>

@interface NSObject (SubclassResponsibility)
- subclassResponsibility:(SEL)aSelector;
@end

@implementation GSSocksParser

- (id)init
{
    if (self = [super init]) {
        configuration = nil;
        address = nil;
        delegate = nil;
        port = 0;
    }
    return self;
}

- (id)initWithConfiguration:(NSDictionary *)aConfiguration
                    address:(NSString *)anAddress
                       port:(NSUInteger)aPort
{
    NSString *version = [aConfiguration objectForKey:NSStreamSOCKSProxyVersionKey];
    version = version ? version : NSStreamSOCKSProxyVersion5;
    
    [self release];
    
    Class concreteClass;
    if ([version isEqualToString:NSStreamSOCKSProxyVersion5]) {
        concreteClass = [GSSocks5Parser class];
    } else if ([version isEqualToString:NSStreamSOCKSProxyVersion4]) {
        concreteClass = [GSSocks4Parser class];
    } else {
        [NSException raise:NSInternalInconsistencyException format:@"Unsupported socks verion: %@", version];
    }
    return [[concreteClass alloc] initWithConfiguration:aConfiguration
                                                address:anAddress 
                                                   port:aPort];
}

- (void)dealloc
{
    [delegate release];
    [address release];
    [configuration release];
    [super dealloc];
}

- (id<GSSocksParserDelegate>)delegate
{
    return delegate;
}

- (void)setDelegate:(id<GSSocksParserDelegate>)aDelegate
{
    id previous = delegate;
    delegate = [aDelegate retain];
    [previous release];
}

- (NSString *)address
{
    return address;
}

- (NSUInteger)port
{
    return port;
}

- (void)start
{
    [self subclassResponsibility:_cmd];
}

- (void)parseNextChunk:(NSData *)aChunk
{
    [self subclassResponsibility:_cmd];
}

@end