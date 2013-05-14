/*
 * Implementation of GNUSTEP key value observing
 * Copyright (C) 2013 Free Software Foundation, Inc.
 *
 * Written by Marat Ibadinov <ibadinov@me.com>
 * Date: 2013
 *
 * This file is part of the GNUstep Base Library.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110 USA.
 *
 * $Date$ $Revision$
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

@interface DirectObservable : NSObject {
    id          _id;
    char        _char;
    double      _double;
    float       _float;
    int         _int;
    long        _long;
    long long   _longLong;
    short       _short;
    NSRange range;
    NSPoint point;
    NSSize  size;
    NSRect  rect;
    id      manual;
}

@end

@interface Observable : DirectObservable {
}

- (void)setId:(id)value;
- (void)setChar:(unsigned char)value;
- (void)setDouble:(double)value;
- (void)setFloat:(float)value;
- (void)setInt:(unsigned int)value;
- (void)setLong:(unsigned long)value;
- (void)setLongLong:(unsigned long long)value;
- (void)setShort:(unsigned short)value;

- (void)setRange:(NSRange)value;
- (void)setPoint:(NSPoint)value;
- (void)setSize:(NSSize)value;
- (void)setRect:(NSRect)value;

@end


@implementation DirectObservable

- (NSString *)description
{
    return @"direct property access";
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)aKey
{
    if ([aKey isEqualToString:@"manual"]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:aKey];
}

@end

@implementation Observable

- (void)setId:(id)value
{
    _id = value;
}

- (void)setChar:(unsigned char)value
{
    _char = value;
}

- (void)setDouble:(double)value
{
    _double = value;
}

- (void)setFloat:(float)value
{
    _float = value;
}

- (void)setInt:(unsigned int)value
{
    _int = value;
}

- (void)setLong:(unsigned long)value
{
    _long = value;
}

- (void)setLongLong:(unsigned long long)value
{
    _longLong = value;
}

- (void)setShort:(unsigned short)value
{
    _short = value;
}

- (void)setRange:(NSRange)value
{
    range = value;
}

- (void)setPoint:(NSPoint)value
{
    point = value;
}

- (void)setSize:(NSSize)value
{
    size = value;
}

- (void)setRect:(NSRect)value
{
    rect = value;
}

- (NSString *)description
{
    return @"setters";
}

@end


@interface Observer : NSObject {
    NSMutableArray *log;
}

- (id)init;
- (void)reset;
- (void)observeValueForKeyPath:(NSString *)aPath ofObject:(id)anObject change:(NSDictionary *)aChange context:(void *)aContext;
- (NSArray *)log;

@end

@implementation Observer

- (id)init
{
    if (self = [super init]) {
        log = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [log release];
    [super dealloc];
}

- (void)reset
{
    [log removeAllObjects];
}

- (void)observeValueForKeyPath:(NSString *)aPath ofObject:(id)anObject change:(NSDictionary *)aChange context:(void *)aContext
{
    [log addObject:aChange];
}

- (NSArray *)log
{
    return log;
}

@end


static void TestAutoKVO(NSObject *observable, NSArray *keys, NSArray *values)
{
    Observer *observer = [Observer new];
    for (NSUInteger index = 0, count = [keys count]; index < count; ++index) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
        NSString *key = [keys objectAtIndex:index];
        [observer reset];
        [observable addObserver:observer forKeyPath:key options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew context:NULL];
        [observable setValue:[values objectAtIndex:index] forKey:key];
        [observable removeObserver:observer forKeyPath:key];
        
        NSMutableArray *log = [NSMutableArray arrayWithCapacity:2];
        NSMutableDictionary *change = [NSMutableDictionary dictionaryWithCapacity:4];
        
        [change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting] forKey:NSKeyValueChangeKindKey];
        [change setObject:[NSNumber numberWithBool:YES] forKey:NSKeyValueChangeNotificationIsPriorKey];
        [log addObject:[[change copy] autorelease]];
        
        [change removeObjectForKey:NSKeyValueChangeNotificationIsPriorKey];
        [change setObject:[values objectAtIndex:index] forKey:NSKeyValueChangeNewKey];
        [log addObject:[[change copy] autorelease]];
        
        PASS([[observer log] isEqual:log], "Automatic KVO works (using %s) for key '%s'", [[observable description] UTF8String], [key UTF8String]);
        
        [pool release];
    }
}

int main()
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    NSArray *keys = [NSArray arrayWithObjects:@"id", @"char", @"double", @"float", @"int", @"long", @"longLong", @"short", @"range", @"point", @"size", @"rect", nil];
    NSArray *values = [NSArray arrayWithObjects:
                       keys,
                       [NSNumber numberWithChar:CHAR_MAX],
                       [NSNumber numberWithDouble:DBL_MAX],
                       [NSNumber numberWithFloat:FLT_MAX],
                       [NSNumber numberWithInt:INT_MAX],
                       [NSNumber numberWithLong:LONG_MAX],
#if defined (_C_LNG_LNG)
                       [NSNumber numberWithLongLong:LONG_LONG_MAX],
#endif
                       [NSNumber numberWithShort:SHRT_MAX],
                       [NSValue valueWithRange:NSMakeRange(0, NSUIntegerMax)],
                       [NSValue valueWithPoint:NSMakePoint(0, CGFLOAT_MAX)],
                       [NSValue valueWithSize:NSMakeSize(0, CGFLOAT_MAX)],
                       [NSValue valueWithRect:NSMakeRect(0, 0, CGFLOAT_MAX, CGFLOAT_MAX)],
                       nil];
    id observable;
    
    observable = [DirectObservable new];
    Observer *observer = [Observer new];
    [observable addObserver:observer forKeyPath:@"manual" options:NSKeyValueObservingOptionPrior context:NULL];
    [observable setValue:keys forKey:@"manual"];
    [observable removeObserver:observer forKeyPath:@"manual"];
    PASS([[observer log] count] == 0, "Direct property access respects +[automaticallyNotifiesObserversForKey:]");
    [observer release];
    TestAutoKVO(observable, keys, values);
    [observable release];
    
    observable = [Observable new];
    Class isa = object_getClass(observable);
    TestAutoKVO(observable, keys, values);
    PASS(object_getClass(observable) == isa, "Object's isa pointer is back to normal");
    [observable release];
    
    [pool release];
}