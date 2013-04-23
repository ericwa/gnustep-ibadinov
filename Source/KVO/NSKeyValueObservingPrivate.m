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

#import "NSKeyValueObservingPrivate.h"
#import "NSKeyValueProperty.h"
#import "NSKeyValueUnnestedProperty.h" /* to support deprecated +[NSObject setKeys:triggerChangeNotificationsForDependentKey:] */
#import "NSKVONotifying.h"

static NSRecursiveLock *kvoLock = nil;
static NSMapTable *kvoTable = nil;
static NSMapTable *propertyTable = nil;
static NSMapTable *replacementTable = nil;

void _NSKVOIntialize(void)
{
    kvoLock = [NSRecursiveLock new];
    kvoTable = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 1024);
    propertyTable = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 1024);
    replacementTable = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSNonOwnedPointerMapValueCallBacks, 64);
}

NSKeyValueProperty *_NSKVOGetPropertyWithKeyPath(Class class, NSString *keyPath)
{
    NSKeyValueProperty *property;
    [kvoLock lock];
    
    NSMapTable *classProperties = [propertyTable objectForKey:class];
    if (!classProperties) {
        classProperties = NSCreateMapTable(NSObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 4);
        [propertyTable setObject:classProperties forKey:class];
    }
    property = [classProperties objectForKey:keyPath];
    if (!property) {
        property = [[NSKeyValueProperty alloc] initWithClass:class keyPath:keyPath];
        [classProperties setObject:property forKey:keyPath];
        [property release];
    }
    
    [kvoLock unlock];
    return property;
}

void _NSKVORegisterUnnestedProperty(Class class, NSString *key, NSArray *affectingKeyPaths)
{
    NSCParameterAssert([key rangeOfString:@"."].location == NSNotFound);
    
    [kvoLock lock];
    
    NSKeyValueProperty *property = [[NSKeyValueUnnestedProperty alloc] initWithClass:class keyPath:key affectingKeyPaths:affectingKeyPaths];
    NSMapTable *classProperties = [propertyTable objectForKey:class];
    if (!classProperties) {
        classProperties = NSCreateMapTable(NSObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 4);
        [propertyTable setObject:classProperties forKey:class];
    }
    [classProperties setObject:property forKey:key];
    
    [kvoLock unlock];
}

void _NSKVOObjectAddObervance(id self, SEL _cmd, NSObject *observer, NSString *keyPath, NSKeyValueObservingOptions options, void *context)
{
    [kvoLock lock];
    
    NSKeyValueProperty *property = _NSKVOGetPropertyWithKeyPath([self class], keyPath);
    NSKeyValueObservance *observance = [[NSKeyValueObservance alloc] initWithObserver:observer ofProperty:property ofObservable:self options:options context:context];
    object_setClass(self, _NSKVOGetNotifyingSubclassOfClass([self class]));
    
    NSKeyValueObservationInfo *info = [self observationInfo];
    if (!info) {
        info = [NSKeyValueObservationInfo new];
        [self setObservationInfo:info];
        [info release];
    }
    [info addObservance:observance];
    
    [kvoLock unlock];
    [[observance property] object:self didAddObservance:observance];
    
    
    [observance lock]; /* todo: should we lock here? */
    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [[NSMutableDictionary alloc] initWithCapacity:2];
        [change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting] forKey:NSKeyValueChangeKindKey];
        if (options & NSKeyValueObservingOptionNew) {
            [change setObject:[self valueForKey:keyPath] forKey:NSKeyValueChangeNewKey];
        }
        NSKeyValueNotifyObserver(self, observance, keyPath, change);
        [change release];
    }
    [observance unlock];
    [observance release];
}

/* 
 * NOTE: observance should never ever be locked while holding kvoLock,
 * locking it will cause a deadlock: oLock->kvoLock vs. kvoLock->oLock
 */
void _NSKVOObjectRemoveObservance(id self, BOOL contextMatters, NSObject *observer, NSString *keyPath, void *context)
{
    NSKeyValueObservance *observance;
    [kvoLock lock];
    
    NSKeyValueObservationInfo *info = [self observationInfo];
    if (contextMatters) {
        observance = [info extractObservanceWithObserver:observer keyPath:keyPath context:context];
    } else
        observance = [info extractObservanceWithObserver:observer keyPath:keyPath];
    
    if (![info hasObservances]) {
        [self setObservationInfo:nil];
    }
    
    [kvoLock unlock];
    
    [[observance property] object:self didRemoveObservance:observance];
    [observance lock];
    [observance invalidate];
    [observance unlock];
}

void _NSKVOObjectDeallocate(id self)
{
    [kvoLock lock];
    NSKeyValueObservationInfo *info = [self observationInfo];
    if ([info hasObservances]) {
        NSLog(@"An instance %lu of class %@ was deallocated while key value observers were still registered with it. "
              @"Observation info was leaked, and may even become mistakenly attached to some other object. "
              @"Set a breakpoint on NSKVODeallocateBreak to stop here in the debugger. "
              @"Here's the current observation info:\n%@", (unsigned long)self, NSStringFromClass([self class]),info);
        NSKVODeallocateBreak();
        abort();
    }
    [kvoLock unlock];
}

void NSKVODeallocateBreak()
{
}

void NSKeyValueNotifyObserver(id self, NSKeyValueObservance *observance, NSString *keyPath, NSDictionary *change)
{
    [observance lock];
    if ([observance isValid]) {
        [self retain];
        [[observance observer] observeValueForKeyPath:keyPath ofObject:self change:change context:[observance context]];
        [self release];
    }
    [observance unlock];
}

void NSKeyValueWillChange(id self, NSString *keyPath, NSDictionary *change)
{
    NSArray *observances;
    [kvoLock lock];
    NSKeyValueObservationInfo *info = [self observationInfo];
    observances = [[info observancesForKeyPath:keyPath] retain];
    [kvoLock unlock];
    
    NSInteger count = [observances count];
    for (NSInteger index = 0; index < count; ++index) {
        NSKeyValueObservance *observance = [observances objectAtIndex:index];
        NSKeyValueProperty *property = [observance property];
        [property object:self withObservance:observance willChangeValue:change forKeyPath:keyPath];
    }
    [observances release];
}

void NSKeyValueDidChange(id self, NSString *keyPath, NSDictionary *change)
{
    NSArray *observances;
    [kvoLock lock];
    NSKeyValueObservationInfo *info = [self observationInfo];
    observances = [[info observancesForKeyPath:keyPath] retain];
    [kvoLock unlock];
    
    NSInteger count = [observances count];
    for (NSInteger index = count - 1; index >= 0; --index) {
        NSKeyValueObservance *observance = [observances objectAtIndex:index];
        NSKeyValueProperty *property = [observance property];
        [property object:self withObservance:observance didChangeValue:change forKeyPath:keyPath];
    }
    
    [observances release];
}

void *_NSKVOObjectGetObservationInfo(id self)
{
    return [kvoTable objectForKey:self];
}

void _NSKVOObjectSetObservationInfo(id self, void *observationInfo)
{
    if (observationInfo) {
        [kvoTable setObject:observationInfo forKey:self];
    } else
        [kvoTable removeObjectForKey:self];
}

Class _NSKVOGetNotifyingSubclassOfClass(Class class)
{
    Class subclass;
    [kvoLock lock];
    subclass = NSMapGet(replacementTable, class);
    [kvoLock unlock];
    return subclass;
}

void _NSKVOEnableAutomaticNotificationForKey(Class class, NSString *key)
{
    [kvoLock lock];
    Class subclass = NSMapGet(replacementTable, class);
    if (!subclass) {
        subclass = [NSKVONotifying _createSubclassOfClass:class];
        NSMapInsert(replacementTable, class, subclass);
    }
    [subclass _replaceSetterForKey:key];
    [kvoLock unlock];
}