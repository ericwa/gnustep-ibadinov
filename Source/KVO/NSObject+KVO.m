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

#import "Foundation/NSKeyValueObserving.h"
#import "NSKeyValueObservingPrivate.h"

@implementation NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)aPath ofObject:(id)anObject change:(NSDictionary *)aChange context:(void *)aContext
{
    [NSException raise:NSInternalInconsistencyException format:
     @"%@: An -%s message was received but not handled.\n"
     @"Key path: %@\n"
     @"Observed object: %@\n"
     @"Change: %@\n"
     @"Context: 0x%lx", self, sel_getName(_cmd), aPath, anObject, aChange, (unsigned long)aContext];
}

@end


@implementation NSObject (NSKeyValueObserverRegistration)

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
    _NSKVOObjectAddObervance(self, _cmd, observer, keyPath, options, context);
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    _NSKVOObjectRemoveObservance(self, NO, observer, keyPath, NULL);
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    _NSKVOObjectRemoveObservance(self, YES, observer, keyPath, context);
}

@end


@implementation NSObject (NSKeyValueObserverNotification)

- (void)willChangeValueForKey:(NSString *)key
{
    NSDictionary *change = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting], NSKeyValueChangeKindKey,
                            [NSNumber numberWithBool:YES], NSKeyValueChangeNotificationIsPriorKey,
                            [self valueForKey:key], NSKeyValueChangeOldKey,
                            nil];
    NSKeyValueWillChange(self, key, change);
}

- (void)didChangeValueForKey:(NSString *)key
{
    NSDictionary *change = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting], NSKeyValueChangeKindKey,
                            [self valueForKey:key], NSKeyValueChangeNewKey,
                            nil];
    NSKeyValueDidChange(self, key, change);
}

- (void)willChange:(NSKeyValueChange)changeKind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:changeKind], NSKeyValueChangeKindKey,
                                   [NSNumber numberWithBool:YES], NSKeyValueChangeNotificationIsPriorKey,
                                   indexes, NSKeyValueChangeIndexesKey,
                                   nil];
    if (changeKind == NSKeyValueChangeRemoval || changeKind == NSKeyValueChangeReplacement) {
        [change setValue:[[self valueForKey:key] objectsAtIndexes:indexes] forKey:NSKeyValueChangeOldKey];
    }
    NSKeyValueWillChange(self, key, change);
}

- (void)didChange:(NSKeyValueChange)changeKind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
    NSMutableDictionary *change = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:changeKind], NSKeyValueChangeKindKey,
                                   indexes, NSKeyValueChangeIndexesKey,
                                   nil];
    if (changeKind == NSKeyValueChangeInsertion || changeKind == NSKeyValueChangeReplacement) {
        [change setObject:[[self valueForKey:key] objectsAtIndexes:indexes] forKey:NSKeyValueChangeNewKey];
    }
    NSKeyValueDidChange(self, key, change);
}

- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutationKind usingObjects:(NSSet *)objects
{
    objects = objects ? objects : [self valueForKey:key];
    NSDictionary *change = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting], NSKeyValueChangeKindKey,
                            [NSNumber numberWithBool:YES], NSKeyValueChangeNotificationIsPriorKey,
                            objects, NSKeyValueChangeOldKey,
                            nil];
    NSKeyValueWillChange(self, key, change);
}

- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutationKind usingObjects:(NSSet *)objects
{
    NSMutableDictionary *change = [NSMutableDictionary dictionaryWithCapacity:3];
    objects = objects ? objects : [self valueForKey:key];
    NSSet *old = nil; /* todo: get it */
    switch (mutationKind) {
        case NSKeyValueUnionSetMutation:
        {
            NSMutableSet *new = [objects mutableCopy];
            [new minusSet:old];
            
            [change setValue:[NSNumber numberWithInt: NSKeyValueChangeInsertion] forKey:NSKeyValueChangeKindKey];
            [change setValue:new forKey:NSKeyValueChangeNewKey];
            
            [new release];
            break;
        }
        case NSKeyValueMinusSetMutation:
        case NSKeyValueIntersectSetMutation:
        {
            old = [old mutableCopy];
            [(NSMutableSet *)old minusSet:objects];
            
            [change setValue:[NSNumber numberWithInt: NSKeyValueChangeRemoval] forKey:NSKeyValueChangeKindKey];
            [change setValue:old forKey:NSKeyValueChangeOldKey];
            
            [old release];
            break;
        }
        case NSKeyValueSetSetMutation:
        {
            old = [old mutableCopy];
            [(NSMutableSet *)old minusSet: objects];
            
            NSMutableSet *new = [objects mutableCopy];
            [new minusSet: old];
            
            [change setValue:[NSNumber numberWithInt: NSKeyValueChangeReplacement] forKey:NSKeyValueChangeKindKey];
            [change setValue:old forKey:NSKeyValueChangeOldKey];
            [change setValue:new forKey:NSKeyValueChangeNewKey];
            
            [old release];
            [new release];
            break;
        }
        default:
            /* todo: raise an exception */
            break;
    }
    NSKeyValueDidChange(self, key, change);
}

@end


@implementation NSObject (NSKeyValueObservingCustomization)

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)aKey
{
    return YES;
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)aKey
{
    return [NSSet set];
}

- (void *)observationInfo
{
    return _NSKVOObjectGetObservationInfo(self);
}

- (void)setObservationInfo:(void *)observationInfo
{
    return _NSKVOObjectSetObservationInfo(self, observationInfo);
}

+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey
{
    _NSKVORegisterUnnestedProperty(self, dependentKey, keys);
}

@end