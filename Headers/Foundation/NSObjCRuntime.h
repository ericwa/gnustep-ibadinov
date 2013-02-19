/** Interface to ObjC runtime for GNUStep
   Copyright (C) 1995, 1997, 2000 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: 1995

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

    AutogsdocSource: NSObjCRuntime.m
    AutogsdocSource: NSLog.m

   */

#ifndef __NSObjCRuntime_h_GNUSTEP_BASE_INCLUDE
#define __NSObjCRuntime_h_GNUSTEP_BASE_INCLUDE

#ifdef __cplusplus
#  ifndef __STDC_LIMIT_MACROS
#    define __STDC_LIMIT_MACROS 1
#  endif
#endif

/* ToDo: remove this hack and supply TargetConditionals.h for other platofrms */
#if !defined (TARGET_OS_WIN32)
#  if defined (GNUSTEP_WITH_DLL)
#    define TARGET_OS_WIN32 1
#  else
#    define TARGET_OS_WIN32 0
#  endif
#endif

/* ToDo: remove this hack and specify NSBUILDINGFOUNDATION when building */
#if !defined (NSBUILDINGFOUNDATION)
#  if defined (BUILD_libgnustep_base_DLL)
#    define NSBUILDINGFOUNDATION 1
#  else
#    define NSBUILDINGFOUNDATION 0
#  endif
#endif

#if defined(__cplusplus)
#  define FOUNDATION_EXTERN extern "C"
#else
#  define FOUNDATION_EXTERN extern
#endif

#if TARGET_OS_WIN32
#  if defined(NSBUILDINGFOUNDATION)
#    define FOUNDATION_EXPORT FOUNDATION_EXTERN __declspec(dllexport)
#  else
#    define FOUNDATION_EXPORT FOUNDATION_EXTERN __declspec(dllimport)
#  endif
#  define FOUNDATION_IMPORT FOUNDATION_EXTERN __declspec(dllimport)
#else
#  define FOUNDATION_EXPORT FOUNDATION_EXTERN
#  define FOUNDATION_IMPORT FOUNDATION_EXTERN
#endif

#if !defined (FOUNDATION_STATIC_INLINE)
#  define FOUNDATION_STATIC_INLINE static __inline__
#endif

#if !defined (FOUNDATION_EXTERN_INLINE)
#  define FOUNDATION_EXTERN_INLINE extern __inline__
#endif

#if !defined(NS_FORMAT_FUNCTION)
#  if defined (__GNUC__) && (__GNUC__ * 10 + __GNUC_MINOR__ >= 42)
#    define NS_FORMAT_FUNCTION(F,A) __attribute__((format(__NSString__, F, A)))
#  else
#    define NS_FORMAT_FUNCTION(F,A)
#  endif
#endif

#if !defined(NS_FORMAT_ARGUMENT)
#  if defined (__GNUC__) && (__GNUC__ * 10 + __GNUC_MINOR__ >= 42)
#    define NS_FORMAT_ARGUMENT(A) __attribute__ ((format_arg(A)))
#  else
#    define NS_FORMAT_ARGUMENT(A)
#  endif
#endif

#ifndef __has_feature
#  define __has_feature(x) 0
#endif

#ifndef NS_RETURNS_RETAINED
#  if __has_feature(attribute_ns_returns_retained)
#    define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
#  else
#    define NS_RETURNS_RETAINED
#  endif
#endif

#ifndef NS_RETURNS_NOT_RETAINED
#  if __has_feature(attribute_ns_returns_not_retained)
#    define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#  else
#    define NS_RETURNS_NOT_RETAINED
#  endif
#endif

#ifndef NS_CONSUMED
#  if __has_feature(attribute_ns_consumed)
#    define NS_CONSUMED __attribute__((ns_consumed))
#  else
#    define NS_CONSUMED
#  endif
#endif

#ifndef NS_CONSUMES_SELF
#  if __has_feature(attribute_ns_consumes_self)
#    define NS_CONSUMES_SELF __attribute__((ns_consumes_self))
#  else
#    define NS_CONSUMES_SELF
#  endif
#endif

#if !defined(NS_INLINE)
#  if defined(__GNUC__)
#    define NS_INLINE static __inline__ __attribute__((always_inline))
#  elif defined(__cplusplus) || defined(__MWERKS__)
#    define NS_INLINE static inline
#  elif defined(_MSC_VER)
#    define NS_INLINE static __inline
#  else
#    define NS_INLINE inline
#  endif
#endif

#ifndef NS_AUTOMATED_REFCOUNT_UNAVAILABLE
#  if __has_feature(objc_arc)
#    define NS_AUTOMATED_REFCOUNT_UNAVAILABLE __attribute__((unavailable("Not available with automatic reference counting")))
#  else
#    define NS_AUTOMATED_REFCOUNT_UNAVAILABLE
#  endif
#endif

#if defined (__clang__)
#  define NS_REQUIRES_NIL_TERMINATION __attribute__((sentinel))
#else
#  define NS_REQUIRES_NIL_TERMINATION
#endif

#import <objc/objc.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>
#include <float.h>

FOUNDATION_EXPORT double NSFoundationVersionNumber;

#if !defined(NSINTEGER_DEFINED)
typedef	intptr_t	NSInteger;
typedef	uintptr_t	NSUInteger;
#endif

#if !defined(NSINTEGER_DEFINED)
#  define NSIntegerMax  INTPTR_MAX
#  define NSIntegerMin  INTPTR_MIN
#  define NSUIntegerMax UINTPTR_MAX
#  define NSINTEGER_DEFINED 1
#endif 

#import	<GNUstepBase/GSVersionMacros.h>
#import	<GNUstepBase/GSConfig.h>
#import	<GNUstepBase/GSBlocks.h>

#if !defined(CGFLOAT_DEFINED)
#  if GS_SIZEOF_VOIDP == 8
#    define CGFLOAT_IS_DBL 1
typedef double CGFloat;
#    define CGFLOAT_MIN DBL_MIN
#    define CGFLOAT_MAX DBL_MAX
#  else
typedef float CGFloat;
#    define CGFLOAT_MIN FLT_MIN
#    define CGFLOAT_MAX FLT_MAX
#  endif
#  define CGFLOAT_DEFINED 1
#endif /* CGFLOAT_DEFINED */

enum
{
    /**
     * Specifies that the enumeration
     * is concurrency-safe.  Note that this does not mean that it will be
     * carried out in a concurrent manner, only that it can be.
     */
    NSEnumerationConcurrent = (1UL << 0), 
    /**
     * Specifies that the enumeration should
     * happen in the opposite of the natural order of the collection.
     */
    NSEnumerationReverse = (1UL << 1) 
};
/**
 * Bitfield used to specify options to control enumeration over collections.
 */
typedef NSUInteger NSEnumerationOptions;

enum
{
    /** 
     * Specifies that the sort
     * is concurrency-safe.  Note that this does not mean that it will be
     * carried out in a concurrent manner, only that it can be.
     */
    NSSortConcurrent = (1UL << 0),
    /**
     * Specifies that the sort should keep
     * equal objects in the same order in the collection.
     */
    NSSortStable = (1UL << 4), 
};
/** 
 * Bitfield used to specify options to control the sorting of collections.
 */
typedef NSUInteger NSSortOptions;

@class Protocol, NSString;

#if OS_API_VERSION(MAC_OS_X_VERSION_10_5, GS_API_LATEST)
FOUNDATION_EXPORT NSString *NSStringFromProtocol(Protocol *aProtocol);
FOUNDATION_EXPORT Protocol *NSProtocolFromString(NSString *aProtocolName);
#endif
    
FOUNDATION_EXPORT SEL       NSSelectorFromString(NSString *aSelectorName);
FOUNDATION_EXPORT NSString  *NSStringFromSelector(SEL aSelector);
    
FOUNDATION_EXPORT Class     NSClassFromString(NSString *aClassName);
FOUNDATION_EXPORT NSString  *NSStringFromClass(Class aClass);
    
FOUNDATION_EXPORT const char *NSGetSizeAndAlignment(const char *typePtr, NSUInteger *sizep, NSUInteger *alignp);

FOUNDATION_EXPORT void NSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT void NSLogv(NSString *format, va_list args) NS_FORMAT_FUNCTION(1,0);

/**
 * Contains values <code>NSOrderedSame</code>, <code>NSOrderedAscending</code>
 * <code>NSOrderedDescending</code>, for left hand side equals, less than, or
 * greater than right hand side.
 */
enum _NSComparisonResult
{
    NSOrderedAscending = -1, NSOrderedSame, NSOrderedDescending
};
typedef NSInteger NSComparisonResult;

enum {NSNotFound = NSIntegerMax};

DEFINE_BLOCK_TYPE(NSComparator, NSComparisonResult, id, id);

#if !defined (YES)
#  define YES (BOOL)1
#endif

#if !defined (NO)
#  define NO (BOOL)0
#endif

#if !defined (nil)
#  define nil 0
#endif

#endif /* __NSObjCRuntime_h_GNUSTEP_BASE_INCLUDE */