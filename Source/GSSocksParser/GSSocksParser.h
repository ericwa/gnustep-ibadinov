#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSStream.h>
#import <Foundation/NSString.h>

@class GSSocksParser;

@protocol GSSocksParserDelegate <NSObject>

- (void)parser:(GSSocksParser *)aParser needsMoreBytes:(NSUInteger)aLength;
- (void)parser:(GSSocksParser *)aParser formedRequest:(NSData *)aRequest;
- (void)parser:(GSSocksParser *)aParser finishedWithAddress:(NSString *)anAddress port:(NSUInteger)aPort;

- (void)parser:(GSSocksParser *)aParser encounteredError:(NSError *)anError;

@end

@interface GSSocksParser : NSObject {
    NSDictionary                *configuration;
    NSString                    *address;
    id<GSSocksParserDelegate>   delegate;
    NSUInteger                  port;
}

- (id)initWithConfiguration:(NSDictionary *)aConfiguration
                    address:(NSString *)anAddress
                       port:(NSUInteger)aPort;

- (id<GSSocksParserDelegate>)delegate;
- (void)setDelegate:(id<GSSocksParserDelegate>)aDelegate;

+ (void)registerSubclass:(Class)aClass forProtocolVersion:(NSString *)aVersion;

- (void)start;
- (void)parseNextChunk:(NSData *)aChunk;

@end