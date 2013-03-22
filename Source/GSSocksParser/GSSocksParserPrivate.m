#import "GSSocksParserPrivate.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCharacterSet.h>
#import <stdio.h>

@implementation NSString (GSSocksParser)

- (NSString *)stringByRepeatingCurrentString:(NSUInteger)times
{
    return [@"" stringByPaddingToLength:times * [self length] withString:self startingAtIndex:0];
}

@end

@implementation GSSocksParser (Private)

- (NSError *)errorWithCode:(NSInteger)aCode description:(NSString *)aDescription
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(aDescription, @"")
                                                         forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:NSStreamSOCKSErrorDomain code:aCode userInfo:userInfo];
}

- (GSSocksAddressType)addressType
{
    if ([address length] > 16) {
        return GSSocksAddressTypeDomain;
    }
    const char *cAddress = [address UTF8String];
    NSUInteger index = 0;
    BOOL hasAlpha = NO, hasDot = NO;
    char character;
    while ((character = cAddress[index])) {
        BOOL isAlpha = character >= 'a' && character <= 'f';
        if (!(character >= '0' && character <= '9') && !isAlpha && character != '.' && character != ':') {
            return GSSocksAddressTypeDomain;
        }
        hasAlpha    = hasAlpha  || isAlpha;
        hasDot      = hasDot    || character == '.';
        ++index;
    }
    return hasAlpha && hasDot ? GSSocksAddressTypeDomain : (hasDot ? GSSocksAddressTypeIPv4 : GSSocksAddressTypeIPv6);
}

- (NSData *)addressData
{
    switch ([self addressType]) {
        case GSSocksAddressTypeIPv4:
        {
            NSMutableData *result = [NSMutableData dataWithLength:4];
            const char *cString = [address UTF8String];
            uint8_t *bytes = [result mutableBytes];
            sscanf(cString, "%hhu.%hhu.%hhu.%hhu", &bytes[0], &bytes[1], &bytes[2], &bytes[3]);
            return result;
        }
        case GSSocksAddressTypeIPv6:
        {
            NSArray *components = [address componentsSeparatedByString:@"::"];
            
            if ([components count] == 2) {
                NSString *leading = [components objectAtIndex:0];
                NSString *trailing = [components objectAtIndex:1];
                NSCharacterSet *charset = [NSCharacterSet characterSetWithCharactersInString:@":"];
                NSUInteger leadingCount = [leading length] ? [[leading componentsSeparatedByCharactersInSet:charset] count] : 0;
                NSUInteger trailingCount = [trailing length] ? [[leading componentsSeparatedByCharactersInSet:charset] count] : 0;
                
                if (leadingCount && trailingCount) {
                    NSString *middle = [@"0:" stringByRepeatingCurrentString:8 - leadingCount - trailingCount];
                    address = [[[leading stringByAppendingString:@":"] stringByAppendingString:middle] stringByAppendingString:trailing];
                } else if (!leadingCount) {
                    NSString *start = [@"0:" stringByRepeatingCurrentString:8 - trailingCount];
                    address = [start stringByAppendingString:trailing];
                } else {
                    NSString *end = [@":0" stringByRepeatingCurrentString:8 - leadingCount];
                    address = [leading stringByAppendingString:end];        
                }
            }
            
            NSMutableData *result = [NSMutableData dataWithLength:16];
            uint16_t *bytes = [result mutableBytes];
            sscanf([address UTF8String], "%hx:%hx:%hx:%hx:%hx:%hx:%hx:%hx",
                   &bytes[0], &bytes[1], &bytes[2], &bytes[3],
                   &bytes[4], &bytes[5], &bytes[6], &bytes[7]);
            return result;
        }
        case GSSocksAddressTypeDomain:
        {
            return [address dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
}

- (NSString *)addressFromData:(NSData *)aData withType:(GSSocksAddressType)anAddressType
{
    switch (anAddressType) {
        case GSSocksAddressTypeIPv4:
        {
            const uint8_t *bytes = [aData bytes];
            return [NSString stringWithFormat:@"%hhu.%hhu.%hhu.%hhu",
                    bytes[0], bytes[1], bytes[2], bytes[3]];
        }
        case GSSocksAddressTypeIPv6:
        {
            const uint16_t *bytes = [aData bytes];
            return [NSString stringWithFormat:@"%hx:%hx:%hx:%hx:%hx:%hx:%hx:%hx",
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7]];
        }
        case GSSocksAddressTypeDomain:
        {
            return [[[NSString alloc] initWithData:aData encoding:NSUTF8StringEncoding] autorelease];
        }
    }
}


@end