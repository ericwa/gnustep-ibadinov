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

#import "NSKVONotifying.h"
#import "NSKeyValueObservingPrivate.h"

static NSString *CreateKeyFromSelector(SEL selector)
{
    const char *name = sel_getName(selector);
    size_t prefixLength = name[0] == '_' ? 4 : 3;
    size_t length = strlen(name) - prefixLength - 1;
    char *key = alloca(length);
    memcpy(key, name + prefixLength, length);
    key[0] = tolower(key[0]);
    return [[NSString alloc] initWithBytes:key length:length encoding:NSUTF8StringEncoding];
}

static struct objc_super GetSuper(id self)
{
    return (struct objc_super){ self, class_getSuperclass(object_getClass(self)) };
}

#define Setter(value)                                                       \
do {                                                                        \
    NSString *key = CreateKeyFromSelector(_cmd);                            \
    [self willChangeValueForKey:key];                                       \
                                                                            \
    struct objc_super super = GetSuper(self);                               \
    typedef void(*ImpType)(struct objc_super *, SEL, __typeof__(value));    \
    ((ImpType)&objc_msgSendSuper)(&super, _cmd, value);                     \
                                                                            \
    [self didChangeValueForKey:key];                                        \
    [key release];                                                          \
} while (0)


@implementation NSKVONotifying

- (void)dealloc
{
    _NSKVOObjectDeallocate(self);
    
    object_setClass(self, [self class]);
    [self dealloc];
    
    if (NO) {
        [super dealloc];
    }
}

- (Class)class
{
    return class_getSuperclass(object_getClass(self));
}

- (Class)superclass
{
    return class_getSuperclass(class_getSuperclass(object_getClass(self)));
}

- (BOOL)_isNSKVONotifying
{
    return YES;
}

- (void)_setter:(void *)value
{
    Setter(value);
}

- (void)_setterChar:(unsigned char)value
{
    Setter(value);
}

- (void)_setterDouble:(double)value
{
    Setter(value);
}

- (void)_setterFloat:(float)value
{
    Setter(value);
}

- (void)_setterInt:(unsigned int)value
{
    Setter(value);
}

- (void)_setterLong:(unsigned long)value
{
    Setter(value);
}

#if defined (_C_LNG_LNG)
- (void)_setterLongLong:(unsigned long long)value
{
    Setter(value);
}
#endif

- (void)_setterShort:(unsigned short)value
{
    Setter(value);
}

- (void)_setterRange:(NSRange)value
{
    Setter(value);
}

- (void)_setterPoint:(NSPoint)value
{
    Setter(value);
}

- (void)_setterSize:(NSSize)value
{
    Setter(value);
}

- (void)_setterRect:(NSRect)value
{
    Setter(value);
}

@end