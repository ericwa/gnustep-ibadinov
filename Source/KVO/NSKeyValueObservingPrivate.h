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
#import "NSKeyValueProperty.h"

FOUNDATION_EXPORT void NSKVODeallocateBreak(void);

FOUNDATION_EXPORT void NSKeyValueNotifyObserver(id self, NSKeyValueObservance *observance, NSString *keyPath, NSDictionary *change);
FOUNDATION_EXPORT void NSKeyValueWillChange(id self, NSString *keyPath, NSDictionary *change);
FOUNDATION_EXPORT void NSKeyValueDidChange(id self, NSString *keyPath, NSDictionary *change);


FOUNDATION_EXPORT void _NSKVOIntialize(void);
FOUNDATION_EXPORT NSKeyValueProperty *_NSKVOGetPropertyWithKeyPath(Class class, NSString *keyPath);

FOUNDATION_EXPORT void _NSKVOObjectDeallocate(id self);

FOUNDATION_EXPORT void *_NSKVOObjectGetObservationInfo(id self);
FOUNDATION_EXPORT void _NSKVOObjectSetObservationInfo(id self, void *observationInfo);

/*
 * has selector as it's second argument just to match a sigature
 * of -[NSObject addObserver:forKeyPath:options:context:]
 */
FOUNDATION_EXPORT void _NSKVOObjectAddObervance(id self, SEL _cmd, NSObject *observer, NSString *keyPath, NSKeyValueObservingOptions options, void *context);
FOUNDATION_EXPORT void _NSKVOObjectRemoveObservance(id self, BOOL contextMatters, NSObject *observer, NSString *keyPath, void *context);


FOUNDATION_EXPORT void _NSKVORegisterUnnestedProperty(Class class, NSString *key, NSArray *affectingKeyPaths);
FOUNDATION_EXPORT void _NSKVOEnableAutomaticNotificationForKey(Class class, NSString *key);
FOUNDATION_EXPORT Class _NSKVOGetNotifyingSubclassOfClass(Class class);