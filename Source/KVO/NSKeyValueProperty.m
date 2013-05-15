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

#import "NSKeyValueProperty.h"
#import "NSKeyValueNestedProperty.h"
#import "NSKeyValueUnnestedProperty.h"
#import "NSKeyValueObservingPrivate.h"

@implementation NSKeyValueProperty

- (id)initWithClass:(Class)aClass keyPath:(NSString *)aPath
{
    if ([self class] != [NSKeyValueProperty class]) {
        if (self = [super init]) {
            containingClass = aClass;
            keyPath = [aPath retain];
        }
        return self;
    }
    
    [self release];
    NSRange range = [aPath rangeOfString:@"."];
    if (range.location == NSNotFound) {
        return [[NSKeyValueUnnestedProperty alloc] initWithClass:aClass keyPath:aPath];
    } else
        return [[NSKeyValueNestedProperty alloc] initWithClass:aClass keyPath:aPath];
}

- (void)dealloc
{
    [keyPath release];
    [super dealloc];
}

- (NSString *)keyPath
{
    return keyPath;
}

- (void)object:(NSObject *)object didAddObservance:(NSKeyValueObservance *)observance
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)object:(NSObject *)object didRemoveObservance:(NSKeyValueObservance *)observance
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance willChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    [observance lock];
    [observance pushChange:change];
    [observance unlock];
    
    NSKeyValueObservingOptions options = [observance options];
    NSObject *observer = [observance observer];
    /* if observer is a property, call appropriate method */
    if (![observer isKindOfClass:[NSKeyValueProperty class]]) {
        if (options & NSKeyValueObservingOptionPrior) {
            if (!(options & NSKeyValueObservingOptionOld)) {
                change = [change mutableCopy];
                [(NSMutableDictionary *)change removeObjectForKey:NSKeyValueChangeOldKey];
            } else 
                [change retain];
            
            NSKeyValueNotifyObserver(object, observance, keyPath, change);
            [change release];
        }
    } else {
        [(NSKeyValueProperty *)observer object:object withObservance:observance willChangeValue:change forKeyPath:aPath];
    }
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance didChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    [observance lock];
    NSDictionary *prior = [observance popChange];
    [observance unlock];
    
    if (prior) {
        NSMutableDictionary *prepared = [[NSMutableDictionary alloc] initWithDictionary:change];
        
        id value;
        NSKeyValueObservingOptions options = [observance options];
        if (!(options & NSKeyValueObservingOptionNew)) {
            [prepared removeObjectForKey:NSKeyValueChangeNewKey];
        } else if (![prepared objectForKey:NSKeyValueChangeNewKey] && (value = [prior objectForKey:NSKeyValueChangeNewKey])) {
            [prepared setObject:value forKey:NSKeyValueChangeNewKey];
        }
        if (options & NSKeyValueObservingOptionOld && (value = [prior objectForKey:NSKeyValueChangeOldKey])) {
            [prepared setObject:value forKey:NSKeyValueChangeOldKey];
        }
        
        /* if observer is a property, call appropriate method */
        NSObject *observer = [observance observer];
        if ([observer isKindOfClass:[NSKeyValueProperty class]]) {
            [(NSKeyValueProperty *)observer object:object withObservance:observance didChangeValue:prepared forKeyPath:aPath];
        } else
            NSKeyValueNotifyObserver(object, observance, keyPath, prepared);
        
        [prepared release];
    }   
}

@end