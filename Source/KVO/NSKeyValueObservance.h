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

#import <Foundation/Foundation.h>

@class NSKeyValueProperty;

@interface NSKeyValueObservance : NSObject<NSLocking> {
    NSRecursiveLock     *lock;
    NSObject            *observer;
    NSKeyValueProperty  *property;
    NSObject            *observable;
    void                *context;
    NSMutableArray      *prior;
    NSUInteger          options;
    BOOL                isValid;
}

- (id)initWithObserver:(NSObject *)anObserver ofProperty:(NSKeyValueProperty *)aProperty ofObservable:(NSObject *)anObservable options:(NSKeyValueObservingOptions)someOptions context:(void *)aContext;

- (NSObject *)observer;
- (NSKeyValueProperty *)property;
- (NSObject *)observable;
- (void *)context;
- (NSUInteger)options;

- (BOOL)isValid;
- (void)invalidate;

- (void)pushChange:(NSDictionary *)aChange;
- (NSDictionary *)popChange;

@end