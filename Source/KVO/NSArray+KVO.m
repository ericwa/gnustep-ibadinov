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
#import "Foundation/NSException.h"
#import "GNUstepBase/NSObject+GNUstepBase.h" /* for notImplemented: */

@implementation NSArray (NSKeyValueObserverRegistration)

- (void)addObserver:(NSObject *)anObserver forKeyPath:(NSString *)aPath options:(NSKeyValueObservingOptions)options context:(void *)aContext
{
    [NSException raise:NSInvalidArgumentException format:@"[%@ %s] is not supported. Key path: %@", self, sel_getName(_cmd), aPath];
}

- (void)removeObserver:(NSObject *)anObserver forKeyPath:(NSString *)keyPath
{
    [NSException raise:NSInvalidArgumentException format:@"[%@ %s] is not supported. Key path: %@", self, sel_getName(_cmd), keyPath];
}

- (void)removeObserver:(NSObject *)anObserver forKeyPath:(NSString *)keyPath context:(void *)context
{
    [NSException raise:NSInvalidArgumentException format:@"[%@ %s] is not supported. Key path: %@", self, sel_getName(_cmd), keyPath];
}

- (void)addObserver:(NSObject *)anObserver toObjectsAtIndexes:(NSIndexSet *)indexes forKeyPath:(NSString *)aPath options:(NSKeyValueObservingOptions)options context:(void *)aContext
{
    /* todo: impelement */
    [self notImplemented:_cmd];
}

- (void)removeObserver:(NSObject *)anObserver fromObjectsAtIndexes:(NSIndexSet *)indexes forKeyPath:(NSString *)aPath
{
    /* todo: implement */
    [self notImplemented:_cmd];
}

@end