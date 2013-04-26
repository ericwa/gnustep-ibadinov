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
        [info release]; /* todo: containter should not retain info */
    }
    [info addObservance:observance];
    
    [kvoLock unlock];
    [[observance property] object:self didAddObservance:observance];
    
    
    [observance lock]; /* todo: should we lock here? */
    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [[NSMutableDictionary alloc] initWithCapacity:2];
        [change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting] forKey:NSKeyValueChangeKindKey];
        if (options & NSKeyValueObservingOptionNew) {
            id value = [self valueForKey:keyPath];
            [change setObject:(value ? value : [NSNull null]) forKey:NSKeyValueChangeNewKey];
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
        object_setClass(self, [self class]);
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

static BOOL NSKVOGetNotifyingSetterForKey(Class class, NSString *key, SEL *originalSetter, SEL *notifyingSetter)
{
    NSUInteger length = [key length];
    NSUInteger size = length + 6;
    char *setter = alloca(size);
    memcpy(setter + 4, [key UTF8String], length);
    setter[0] = '_';
    setter[1] = 's';
    setter[2] = 'e';
    setter[3] = 't';
    setter[4] = toupper(setter[4]);
    setter[size - 2] = ':';
    setter[size - 1] = '\0';
    
    const char *type = NULL;
    
    SEL selector = sel_getUid(setter + 1);
    NSMethodSignature *signature = [class instanceMethodSignatureForSelector:selector];
    if (!signature) {
        selector = sel_getUid(setter);
        signature = [class instanceMethodSignatureForSelector:selector];
    }
    if (!signature) {
        /* if direct access is enables for this property, KVC will notify */
        return NO;
    }
    type = [signature getArgumentTypeAtIndex:2];
    const char *selectorName;
    switch (type[0]) {
        case GSObjCTypeChar:
        case GSObjCTypeUnsignedChar:
            selectorName = "_setterChar:";
            break;
        case GSObjCTypeShort:
        case GSObjCTypeUnsignedShort:
            selectorName = "_setterShort:";
            break;
        case GSObjCTypeInt:
        case GSObjCTypeUnsignedInt:
            selectorName = "_setterInt:";
            break;
        case GSObjCTypeLong:
        case GSObjCTypeUnsignedLong:
            selectorName = "_setterLong:";
            break;
        case GSObjCTypeLongLong:
        case GSObjCTypeUnsignedLongLong:
            selectorName = "_setterLongLong:";
            break;
        case GSObjCTypeId:
        case GSObjCTypePointer:
        case GSObjCTypeCharPointer:
            selectorName = "_setter:";
            break;
        case GSObjCTypeFloat:
            selectorName = "_setterFloat:";
            break;
        case GSObjCTypeDouble:
            selectorName = "_setterDouble:";
            break;
        case GSObjCTypeStructureBegin:
            /* todo: use valid type comparison function */
            if (strcmp(type, @encode(NSRange)) == 0) {
                selectorName = "_setterRange:";
                break;
            }
            if (strcmp(type, @encode(NSPoint)) == 0) {
                selectorName = "_setterPoint:";
                break;
            }
            if (strcmp(type, @encode(NSSize)) == 0) {
                selectorName = "_setterSize:";
                break;
            }
            if (strcmp(type, @encode(NSRect)) == 0) {
                selectorName = "_setterRect:";
                break;
            }
        default:
            return NO;
    }
    if (originalSetter) {
        *originalSetter = selector;
    }
    if (notifyingSetter) {
        *notifyingSetter = sel_getUid(selectorName);
    }
    return YES;
}

/*
 * NOTE!
 * From "Ensuring KVC compliance": (... requires that your class:) Implement a method
 * named -<key>, -is<Key>,  or have an instance variable <key> or _<key>
 */
static BOOL NSKVOGetIvarNameForKey(Class class, NSString *key, NSString **ivarName)
{
    NSUInteger length = [key length];
    char *name = alloca(length + 2);
    memcpy(name + 1, [key UTF8String], length);
    name[0] = '_';
    name[length + 1] = '\0';
    
    for (int probe = 0; probe < 2; ++probe) {
        for (int offset = 0; offset < 2; ++offset) {
            if (class_getInstanceVariable(class, name + offset)) {
                if (ivarName) {
                    *ivarName = [NSString stringWithUTF8String:name + offset];
                }
                return YES;
            }
        }
        name[1] = tolower(name[1]);
    }
    
    return NO;
}

/*
 * NOTE!
 * Should only be called while holding kvoLock
 */
static Class NSKVOMakeNotifyingSubclassOfClass(Class class)
{
    Class prototype = [NSKVONotifying class];
    Class subclass = NSMapGet(replacementTable, class);
    
    if (!subclass) {
        subclass = objc_allocateClassPair(class, [[NSString stringWithFormat:@"NSKVONotifying_%s", class_getName(class)] UTF8String], 0);
        
        static int const SelectorCount = 4;
        SEL selectors[SelectorCount] = {@selector(dealloc), @selector(class), @selector(superclass), @selector(_isNSKVONotifying)};
        for (int index = 0; index < SelectorCount; ++index) {
            Method method = class_getInstanceMethod(prototype, selectors[index]);
            class_replaceMethod(subclass, selectors[index], method_getImplementation(method), method_getTypeEncoding(method));
        }
        
        objc_registerClassPair(subclass);
        NSMapInsert(replacementTable, class, subclass);
    }
    return subclass;
}

Class _NSKVOGetNotifyingSubclassOfClass(Class class)
{
    Class subclass;
    [kvoLock lock];
    subclass = NSMapGet(replacementTable, class);
    [kvoLock unlock];
    return subclass ? subclass : class;
}

void _NSKVOEnableAutomaticNotificationForKey(Class class, NSString *key)
{
    [kvoLock lock];
    SEL originalSetter, notifyingSetter;
    if (NSKVOGetNotifyingSetterForKey(class, key, &originalSetter, &notifyingSetter)) {
        Class subclass = NSKVOMakeNotifyingSubclassOfClass(class);
        Method notifyingMethod = class_getInstanceMethod([NSKVONotifying class], notifyingSetter);
        Method originalMethod = class_getInstanceMethod(class, originalSetter); /* to preserve type encoding */
        class_replaceMethod(subclass, originalSetter, method_getImplementation(notifyingMethod), method_getTypeEncoding(originalMethod));
    } else if (NSKVOGetIvarNameForKey(class, key, nil)) {
        /* a hack in KVC relies on _isKVONotifying method presence */
        NSKVOMakeNotifyingSubclassOfClass(class);
    }
    [kvoLock unlock];
}