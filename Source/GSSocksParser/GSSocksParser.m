#import "GSSocksParser.h"
#import <Foundation/NSException.h>

static NSMutableDictionary *GSSocksParserSubclasses;

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
    NSString *version = NSStreamSOCKSProxyVersion5;
    if ([aConfiguration objectForKey:NSStreamSOCKSProxyVersionKey]) {
        version = [aConfiguration objectForKey:NSStreamSOCKSProxyVersionKey];
    }
    [self release];
    return [[[GSSocksParserSubclasses objectForKey:version] alloc] initWithConfiguration:aConfiguration
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

+ (void)registerSubclass:(Class)aClass forProtocolVersion:(NSString *)aVersion
{
    if ([GSSocksParserSubclasses objectForKey:aVersion]) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"More than one subclass for SOCKS protocol version: %@", aVersion];
    }
    [GSSocksParserSubclasses setObject:aClass forKey:aVersion];
}

+ (void)load
{
    GSSocksParserSubclasses = [[NSMutableDictionary alloc] initWithCapacity:2];
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