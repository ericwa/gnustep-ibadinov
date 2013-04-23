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

#import "NSKeyValueNestedProperty.h"
#import "NSKeyValueUnnestedProperty.h"
#import "NSKeyValueObservingPrivate.h"

static NSKeyValueObservingOptions const ObservingOptions = NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;

@implementation NSKeyValueNestedProperty

- (id)initWithClass:(Class)aClass keyPath:(NSString *)aPath
{
    if (self = [super initWithClass:aClass keyPath:aPath]) {
        NSRange range = [aPath rangeOfString:@"."];
        key = [[aPath substringToIndex:range.location] retain];
        
        NSKeyValueUnnestedProperty *property = (NSKeyValueUnnestedProperty *)_NSKVOGetPropertyWithKeyPath(aClass, key);
        if (![property hasDependencies]) {
            keyPathTail = [[aPath substringFromIndex:NSMaxRange(range)] retain];
        } else
            keyPathTail = nil;
    }
    return self;
}

- (void)object:(NSObject *)object didAddObservance:(NSKeyValueObservance *)observance
{
    [object addObserver:self forKeyPath:key options:ObservingOptions context:observance];
    if (keyPathTail) {
        object = [object valueForKey:key];
        [object addObserver:self forKeyPath:keyPathTail options:ObservingOptions context:observance];
    }
}

- (void)object:(NSObject *)object didRemoveObservance:(NSKeyValueObservance *)observance
{
    [object removeObserver:self forKeyPath:key context:observance];
    if (keyPathTail) {
        object = [object valueForKey:key];
        [object removeObserver:self forKeyPath:keyPathTail context:observance];
    }    
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance willChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    observance = [observance context];
    
    /* if value for self.key will change, take a value of tail, otherwise it's already there */
    if (object == [observance observable]) {
        change = [[change mutableCopy] autorelease];
        [(NSMutableDictionary *)change setObject:[object valueForKeyPath:keyPath] forKey:NSKeyValueChangeOldKey];
    }
    
    [super object:[observance observable] withObservance:observance willChangeValue:change forKeyPath:keyPath];
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance didChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    observance = [observance context];
    /* if value for self.key has changed, register self as tail observer once again and take it's value */
    if (object == [observance observable]) {
        if (keyPathTail) {
            /* todo: deal with recursive change of self.key */
            [[change objectForKey:NSKeyValueChangeOldKey] removeObserver:self forKeyPath:keyPathTail context:observance];
            [[change objectForKey:NSKeyValueChangeNewKey] addObserver:self forKeyPath:keyPathTail options:ObservingOptions context:observance];
        }
        change = [[change mutableCopy] autorelease];
        [(NSMutableDictionary *)change setObject:[object valueForKeyPath:keyPath] forKey:NSKeyValueChangeNewKey];
    }
    
    [super object:[observance observable] withObservance:observance didChangeValue:change forKeyPath:keyPath];
}

@end