#import "GSSocksParser.h"

@interface GSSocks5Parser : GSSocksParser {
    NSUInteger  state;
    NSUInteger  addressSize;
    uint8_t     addressType;
    BOOL        stopped;
}

@end