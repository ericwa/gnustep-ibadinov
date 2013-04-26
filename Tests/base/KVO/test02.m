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

#import "Testing.h"
#import <Foundation/Foundation.h>

@interface Observable : NSObject {
    id _id;
    NSMutableArray *_array;
    NSMutableSet   *_set;
}

- (void)insertElements:(NSArray *)elements;
- (void)removeElementsAtIndexes:(NSIndexSet *)indexes;
- (void)replaceElementsAtIndexes:(NSIndexSet *)indexes withElements:(NSArray *)replacement;

- (void)unionSet:(NSSet *)set;
- (void)minusSet:(NSSet *)set;
- (void)intersectSet:(NSSet *)set;
- (void)setSet:(NSSet *)set;

@end

@implementation Observable

- (id)init
{
    if (self = [super init]) {
        _id = nil;
        _array = [NSMutableArray new];
        _set = [NSMutableSet new];
    }
    return self;
}

- (void)dealloc
{
    [_set release];
    [_array release];
    [super dealloc];
}

- (void)insertElements:(NSArray *)elements
{
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange([_array count], [elements count])];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"array"];
    [_array addObjectsFromArray:elements];
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"array"];
}

- (void)removeElementsAtIndexes:(NSIndexSet *)indexes
{
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"array"];
    [_array removeObjectsAtIndexes:indexes];
    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"array"];
}

- (void)replaceElementsAtIndexes:(NSIndexSet *)indexes withElements:(NSArray *)replacement
{
    [self willChange:NSKeyValueChangeReplacement valuesAtIndexes:indexes forKey:@"array"];
    [_array replaceObjectsAtIndexes:indexes withObjects:replacement];
    [self didChange:NSKeyValueChangeReplacement valuesAtIndexes:indexes forKey:@"array"];
}

- (void)unionSet:(NSSet *)set
{
    [self willChangeValueForKey:@"set" withSetMutation:NSKeyValueUnionSetMutation usingObjects:set];
    [_set unionSet:set];
    [self didChangeValueForKey:@"set" withSetMutation:NSKeyValueUnionSetMutation usingObjects:set];
}

- (void)minusSet:(NSSet *)set
{
    [self willChangeValueForKey:@"set" withSetMutation:NSKeyValueMinusSetMutation usingObjects:set];
    [_set minusSet:set];
    [self didChangeValueForKey:@"set" withSetMutation:NSKeyValueMinusSetMutation usingObjects:set];
}

- (void)intersectSet:(NSSet *)set
{
    [self willChangeValueForKey:@"set" withSetMutation:NSKeyValueIntersectSetMutation usingObjects:set];
    [_set intersectSet:set];
    [self didChangeValueForKey:@"set" withSetMutation:NSKeyValueIntersectSetMutation usingObjects:set];
}

- (void)setSet:(NSSet *)set
{
    [self willChangeValueForKey:@"set" withSetMutation:NSKeyValueSetSetMutation usingObjects:set];
    _set = [set mutableCopy];
    [self didChangeValueForKey:@"set" withSetMutation:NSKeyValueSetSetMutation usingObjects:set];
}

@end


@interface Observer1 : NSObject {
    NSMutableArray *log;
}

- (NSArray *)log;
- (void)reset;

@end

@implementation Observer1

- (id)init
{
    if (self = [super init]) {
        log = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [log release];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSMutableDictionary *preparedChange = [[NSMutableDictionary alloc] initWithCapacity:[change count]];
    NSEnumerator *enumerator = [change keyEnumerator];
    id key;
    while ((key = [enumerator nextObject])) {
        id object = [change objectForKey:key];
        if ([object isKindOfClass:[NSIndexSet class]]) {
            NSUInteger *indexes = alloca(sizeof(NSUInteger) * 16);
            NSUInteger count = [object getIndexes:indexes maxCount:16 inIndexRange:nil];
            object = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger index = 0; index < count; ++index) {
                [object addObject:[NSString stringWithFormat:@"%lu", (unsigned long)indexes[index]]];
            }
        } else if ([object isKindOfClass:[NSSet class]]) {
            object = [[object allObjects] sortedArrayUsingSelector:@selector(compare:)];
        } else if ([object isKindOfClass:[NSNumber class]]) {
            object = [object stringValue];
        } else if (object == [NSNull null]) {
            object = [object description];
        } else if (![object isKindOfClass:[NSString class]] && ![object isKindOfClass:[NSArray class]]) {
            object = [object className];
        }
        [preparedChange setObject:object forKey:key];
    }
    [log addObject:preparedChange];
    [preparedChange release];
}

- (NSArray *)log
{
    return log;
}

- (void)reset
{
    [log removeAllObjects];
}

@end


int main()
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Observable *observable = [Observable new];
    Observer1 *observer = [Observer1 new];
    NSArray *log;
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
    NSString *idKey = @"id";
    NSString *arrayKey = @"array";
    NSString *setKey = @"set";
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:@"test02"];
    
    
    [observable addObserver:observer forKeyPath:idKey options:options context:NULL];
    [observable setValue:observable forKey:idKey];
    [observable setValue:nil forKey:idKey];
    [observable removeObserver:observer forKeyPath:idKey];
    log = [NSArray arrayWithContentsOfFile:@"NilValue.plist"];
    PASS([[observer log] isEqual:log], "KVO correctly handles nil values");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:arrayKey options:options context:NULL];
    [observable insertElements:[NSArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", nil]];
    [observable removeObserver:observer forKeyPath:arrayKey];
    log = [NSArray arrayWithContentsOfFile:@"ItemInsertion.plist"];
    PASS([[observer log] isEqual:log], "KVO correctly handles array item insertion");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:arrayKey options:options context:NULL];
    [observable removeElementsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(3, 2)]];
    [observable removeObserver:observer forKeyPath:arrayKey];
    log = [NSArray arrayWithContentsOfFile:@"ItemRemoval.plist"];
    PASS([[observer log] isEqual:log], "KVO correctly handles array item removal");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:arrayKey options:options context:NULL];
    [observable replaceElementsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 3)] withElements:[NSArray arrayWithObjects:@"c", @"d", @"e", nil]];
    [observable removeObserver:observer forKeyPath:arrayKey];
    log = [NSArray arrayWithContentsOfFile:@"ItemReplacement.plist"];
    PASS([[observer log] isEqual:log], "KVO correctly handles array item replacement");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable setSet:nil];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetSettingNil.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles set setting (empty -> nil)");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable setSet:[NSSet set]];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetSettingEmpty.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles set setting (nil -> empty)");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable setSet:[NSSet setWithObjects:@"a", @"b", @"c", @"d", nil]];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetSettingNotEmpty.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles set setting (empty -> not empty)");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable unionSet:[NSSet setWithObjects:@"c", @"d", @"e", @"f", nil]];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetUnion.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles set union");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable minusSet:[NSSet setWithObjects:@"b", @"d", @"x", nil]];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetComplementation.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles relative set complementation");
    
    
    [observer reset];
    [observable addObserver:observer forKeyPath:setKey options:options context:NULL];
    [observable intersectSet:[NSSet setWithObjects:@"a", @"c", @"e", @"x", @"y", @"z", nil]];
    [observable removeObserver:observer forKeyPath:setKey];
    log = [NSArray arrayWithContentsOfFile:@"SetIntersection.plist"];
    PASS([[observer log] isEqual:log], "KVO corretly handles set intersection");
    
    
    [observer release];
    [observable release];
    [pool release];
}