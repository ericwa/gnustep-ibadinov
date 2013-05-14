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

#import "NSKeyValueObservationInfo.h"

@implementation NSKeyValueObservationInfo

- (id)init
{
    if (self = [super init]) {
        observances = [NSMutableDictionary new];
    }
    return self;
}

- (void)dealloc
{
    [observances release];
    [super dealloc];
}

- (BOOL)hasObservances
{
    return [observances count] != 0;
}

-(NSArray *)observancesForKeyPath:(NSString *)keyPath
{
    return [[[observances objectForKey:keyPath] copy] autorelease];
}

- (void)addObservance:(NSKeyValueObservance *)anObservance
{
    NSString *keyPath = [[anObservance property] keyPath];
    if (![observances objectForKey:keyPath]) {
        NSMutableArray *pathObservances = [NSMutableArray new];
        [observances setObject:pathObservances forKey:keyPath];
        [pathObservances release];
    }
    [[observances objectForKey:keyPath] addObject:anObservance];
}

- (NSKeyValueObservance *)_extractObservanceWithObserver:(NSObject *)observer keyPath:(NSString *)keyPath context:(void *)context contextMatters:(BOOL)contextMatters
{
    NSKeyValueObservance *result = nil;
    NSMutableArray *pathObservances = [observances objectForKey:keyPath];
    NSInteger count = [pathObservances count];
    for (NSInteger index = count - 1; index >= 0; --index) {
        NSKeyValueObservance *observance = [pathObservances objectAtIndex:index];
        BOOL match = contextMatters ? ([observance observer] == observer && [observance context] == context) : [observance observer] == observer;
        
        if (match) {
            result = [observance retain];
            [pathObservances removeObjectAtIndex:index];
            --count;
            break;
        }
    }
    if (!count) {
        [observances removeObjectForKey:keyPath];
    }
    return [result autorelease];
}

- (NSKeyValueObservance *)extractObservanceWithObserver:(NSObject *)observer keyPath:(NSString *)keyPath
{
    return [self _extractObservanceWithObserver:observer keyPath:keyPath context:NULL contextMatters:NO];
}

- (NSKeyValueObservance *)extractObservanceWithObserver:(NSObject *)observer keyPath:(NSString *)keyPath context:(void *)context
{
    return [self _extractObservanceWithObserver:observer keyPath:keyPath context:context contextMatters:YES];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSKeyValueObservationInfo 0x%lx> %@", (unsigned long)self, observances];
}

@end