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

static void ReplaceMethod(Class ofClass, Class fromClass, SEL selector)
{
    Method method = class_getInstanceMethod(fromClass, selector);
    class_replaceMethod(ofClass, selector, method_getImplementation(method), method_getTypeEncoding(method));
}

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

#define Setter(value)                               \
do {                                                \
    NSString *key = CreateKeyFromSelector(_cmd);    \
    [self willChangeValueForKey:key];               \
                                                    \
    struct objc_super super = GetSuper(self);       \
    objc_msgSendSuper(&super, _cmd, value);         \
                                                    \
    [self didChangeValueForKey:key];                \
    [key release];                                  \
} while (0)


@implementation NSKVONotifying

+ (Class)_createSubclassOfClass:(Class)aClass
{
    Class prototype = objc_getClass("NSKVONotifying");
    Class result = objc_allocateClassPair(aClass, [[NSString stringWithFormat:@"NSKVONotifying_%s", class_getName(aClass)] UTF8String], 0);
    ReplaceMethod(result, prototype, @selector(dealloc));
    ReplaceMethod(result, prototype, @selector(class));
    ReplaceMethod(result, prototype, @selector(superclass));
    ReplaceMethod(result, prototype, @selector(_isNSKVONotifying));
    ReplaceMethod(object_getClass(result), object_getClass(prototype), @selector(_replaceSetterForKey:));
    return result;
}

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

+ (SEL)_notifyingSetterForKey:(NSString *)key originalSetter:(SEL *)originalSetter
{
    NSString *capitalizedName = [key capitalizedString];
    const char *type = NULL;
    
    SEL selector = sel_getUid([[NSString stringWithFormat:@"set%@:", capitalizedName] UTF8String]);
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    if (!signature) {
        selector = sel_getUid([[NSString stringWithFormat:@"_set%@:", capitalizedName] UTF8String]);
        signature = [[self class] instanceMethodSignatureForSelector:selector];
    }
    if (!signature) {
        /* if direct access is enables for this property, KVC will notify */
        return NULL;
    }
    type = [signature getArgumentTypeAtIndex:3];
    const char *selectorName;
    switch (type[0]) {
        case GSObjCTypeChar:
        case GSObjCTypeUnsignedChar:
            selectorName = "_setterChar";
        case GSObjCTypeShort:
        case GSObjCTypeUnsignedShort:
            selectorName = "_setterShort";
        case GSObjCTypeInt:
        case GSObjCTypeUnsignedInt:
            selectorName = "_setterInt";
        case GSObjCTypeLong:
        case GSObjCTypeUnsignedLong:
            selectorName = "_setterLong";
        case GSObjCTypeLongLong:
        case GSObjCTypeUnsignedLongLong:
            selectorName = "_setterLongLong";
        case GSObjCTypeId:
        case GSObjCTypePointer:
        case GSObjCTypeCharPointer:
            selectorName = "_setter";
            break;
        case GSObjCTypeStructureBegin:
            /* todo: use valid type comparison function */
            if (!strcmp(type, @encode(NSRange))) {
                selectorName = "_setterRange";
                break;
            }
            if (!strcmp(type, @encode(NSPoint))) {
                selectorName = "_setterPoint";
                break;
            }
            if (!strcmp(type, @encode(NSSize))) {
                selectorName = "_setterSize";
                break;
            }
            if (!strcmp(type, @encode(NSRect))) {
                selectorName = "_setterRect";
                break;
            }
        default:
            /* todo: emit error? */
            return NULL;
    }
    if (originalSetter) {
        *originalSetter = selector;
    }
    return sel_getUid(selectorName);
}

+ (void)_replaceSetterForKey:(NSString *)key
{
    SEL originalSetter;
    SEL notifiyingSetter = [self _notifyingSetterForKey:key originalSetter:&originalSetter];
    if (notifiyingSetter) {
        Method method = class_getInstanceMethod(objc_getClass("NSKVONotifying"), notifiyingSetter);
        class_replaceMethod(self, originalSetter, method_getImplementation(method), method_getTypeEncoding(method));
    }
}

@end