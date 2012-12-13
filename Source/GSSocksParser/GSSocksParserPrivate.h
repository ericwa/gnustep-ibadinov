#import "GSSocksParser.h"

typedef enum GSSocksAddressType {
    GSSocksAddressTypeIPv4     = 0x1,
    GSSocksAddressTypeIPv6     = 0x4,
    GSSocksAddressTypeDomain   = 0x3,
} GSSocksAddressType;

@interface GSSocksParser (Private)

- (NSError *)errorWithCode:(NSInteger)aCode description:(NSString *)aDescription;


- (GSSocksAddressType)addressType;

- (NSData *)addressData;
- (NSString *)addressFromData:(NSData *)aData withType:(GSSocksAddressType)anAddressType;

@end