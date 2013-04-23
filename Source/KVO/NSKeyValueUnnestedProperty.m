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

#import "NSKeyValueUnnestedProperty.h"
#import "NSKeyValueObservingPrivate.h"

@implementation NSKeyValueUnnestedProperty

- (id)initWithClass:(Class)aClass keyPath:(NSString *)aPath affectingKeyPaths:(NSArray *)paths
{
    if (self = [super initWithClass:aClass keyPath:aPath]) {
        affectingKeyPaths = [paths retain];
    }
    if ([aClass automaticallyNotifiesObserversForKey:aPath]) {
        /* todo: decide a code path for properties with no setter */
        _NSKVOEnableAutomaticNotificationForKey(containingClass, keyPath);
    }
    return self;
}

- (id)initWithClass:(Class)aClass keyPath:(NSString *)aPath
{
    NSSet *paths = [aClass keyPathsForValuesAffectingValueForKey:aPath];
    
    SEL propertySpecificSelector = sel_getUid([[NSString stringWithFormat:@"keyPathsForValuesAffecting%@", [aPath capitalizedString]] UTF8String]);
    if (class_respondsToSelector(object_getClass(aClass), propertySpecificSelector)) {
        paths = [paths setByAddingObjectsFromSet:objc_msgSend(aClass, propertySpecificSelector)];
    }
    
    return [self initWithClass:aClass keyPath:aPath affectingKeyPaths:[paths allObjects]];
}

- (void)dealloc
{
    [affectingKeyPaths dealloc];
    [super dealloc];
}

- (BOOL)hasDependencies
{
    return [affectingKeyPaths count] != 0;
}

- (void)object:(NSObject *)object didAddObservance:(NSKeyValueObservance *)observance
{
    NSKeyValueObservingOptions options = [observance options] & NSKeyValueObservingOptionPrior;
    for (NSString *path in affectingKeyPaths) {
        [object addObserver:self forKeyPath:path options:options context:observance];
    }
}

- (void)object:(NSObject *)object didRemoveObservance:(NSKeyValueObservance *)observance
{
    for (NSString *path in affectingKeyPaths) {
        [object removeObserver:self forKeyPath:path context:observance];
    }
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance willChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    /* forward notifications from affecting keys */
    if ([observance observer] == self) {
        observance = [observance context];
        object = [observance observable];
        aPath = keyPath;
        change = [[change mutableCopy] autorelease];
        [(NSMutableDictionary *)change setObject:[object valueForKeyPath:keyPath] forKey:NSKeyValueChangeOldKey];
    }
    
    [super object:object withObservance:observance willChangeValue:change forKeyPath:aPath];
}

- (void)object:(NSObject *)object withObservance:(NSKeyValueObservance *)observance didChangeValue:(NSDictionary *)change forKeyPath:(NSString *)aPath
{
    /* forward notifications from affecting keys */
    if ([observance observer] == self) {
        observance = [observance context];
        object = [observance observable];
        aPath = keyPath;
        change = [[change mutableCopy] autorelease];
        [(NSMutableDictionary *)change setObject:[object valueForKeyPath:keyPath] forKey:NSKeyValueChangeNewKey];
    }
    
    [super object:object withObservance:observance didChangeValue:change forKeyPath:aPath];
}

@end