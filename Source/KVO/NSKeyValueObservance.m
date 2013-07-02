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

#import "NSKeyValueObservance.h"

NS_INLINE NSString *BooleanDescription(BOOL value)
{
    return value ? @"YES" : @"NO";
}

@implementation NSKeyValueObservance

- (id)initWithObserver:(NSObject *)anObserver ofProperty:(NSKeyValueProperty *)aProperty ofObservable:(NSObject *)anObservable options:(NSKeyValueObservingOptions)someOptions context:(void *)aContext
{
    if (self = [super init]) {
        lock = [NSRecursiveLock new];
        observer = anObserver;
        property = aProperty;
        observable = anObservable;
        options = someOptions;
        context = aContext;
        prior = [NSMutableArray new];
        isValid = YES;
    }
    return self;
}

- (void)dealloc
{
    [prior release];
    [lock release];
    [super dealloc];
}

- (void)lock
{
    [lock lock];
}

- (void)unlock
{
    [lock unlock];
}

- (NSObject *)observer
{
    return observer;
}

- (NSKeyValueProperty *)property
{
    return property;
}

- (NSObject *)observable
{
    return observable;
}

- (void *)context
{
    return context;
}

- (NSUInteger)options
{
    return options;
}

- (BOOL)isValid
{
    return isValid;
}

- (void)invalidate
{
    isValid = NO;
}

- (void)pushChange:(NSDictionary *)aChange
{
    [prior addObject:aChange];
}

- (NSDictionary *)popChange
{
    NSDictionary *change = [prior lastObject];
    if (change) {
        [prior removeLastObject];
    }
    return change;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSKeyValueObservance 0x%lx: Observer: 0x%lx, Key path: %@, Options: <New: %@, Old: %@, Prior: %@> Context: 0x%lx>",
            (unsigned long)self,
            (unsigned long)observer,
            [property keyPath],
            BooleanDescription(options & NSKeyValueObservingOptionNew),
            BooleanDescription(options & NSKeyValueObservingOptionOld),
            BooleanDescription(options & NSKeyValueObservingOptionPrior),
            (unsigned long)context];
}

@end