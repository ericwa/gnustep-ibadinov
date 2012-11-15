#if defined (NeXT_RUNTIME) && (defined (__x86_64__) || defined (__x86_64))

#import <Foundation/NSInvocation.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSNull.h>
#import <GNUstepBase/GSObjCRuntime.h>
#import <objc/message.h>
#import <string.h>
#import <stdlib.h>

#undef  MAX
#define MAX(a, b)                         \
({                                        \
  typeof(a) __a = a; typeof(b) __b = b;   \
  __a > __b ? __a : __b;                  \
})

@interface NSMethodSignature (Private)

- (const char *)methodType;

@end

extern SEL forwardSelector;

typedef struct SmallStructureInfo
{
  uint8_t offset1; /* allways  < 208 */
  uint8_t offset2; /* allways  < 208 */
  uint8_t size1;   /* allways  = 8 */
  uint8_t size2;   /* allways <= 8 */
} SmallStructureInfo;

/*
 * struct marg_list_layout
 * {
 *    __float128  floatingPointArgs[8];	// xmm0 .. xmm7
 *    long        linkageArea[4];         // r10, rax, ebp, ret
 *    long        registerArgs[6];        // rdi, rsi, rdx, rcx, r8, r9
 *    long        stackArgs[0];           // variable-size
 * }
 */

static uint32_t const OffsetFloat     = 0;
static uint32_t const OffsetRegister  = OffsetFloat + 16 * 8;
static uint32_t const OffsetLink      = OffsetRegister + 8 * 6;
static uint32_t const OffsetStack     = OffsetLink + 8 * 4;

static uint32_t const ArgumentListMinSize   = 208;
static uint8_t  const StackAlignment        = 16;
static uint8_t  const MaxArgumentCount      = 32;

typedef enum StorageType
{
  StorageTypeXmm       = 0x1,
  StorageTypeInt       = 0x2,
  StorageTypeStack     = 0x3,
  StorageTypeIntInt    = 0x4,
  StorageTypeIntXmm    = 0x5,
  StorageTypeXmmXmm    = 0x6,
  StorageTypeXmmInt    = 0x7
} StorageType;

static uint8_t const WordSize = sizeof(void *);
static uint8_t const FloatSize = sizeof(double) * 2;

static uint8_t StorageTypeTransitions[8][8] = {
  [0] = {
    [StorageTypeXmm]    = StorageTypeXmm,
    [StorageTypeInt]    = StorageTypeInt,
  },
  [StorageTypeXmm] = {
    [StorageTypeXmm]    = StorageTypeXmmXmm,
    [StorageTypeInt]    = StorageTypeXmmInt,
  },
  [StorageTypeInt] = {
    [StorageTypeXmm]    = StorageTypeIntXmm,
    [StorageTypeInt]    = StorageTypeIntInt,
  },
  [StorageTypeIntInt] = {
    [StorageTypeXmm]    = StorageTypeStack,
    [StorageTypeInt]    = StorageTypeStack,
  },
  [StorageTypeIntXmm] = {
    [StorageTypeXmm]    = StorageTypeStack,
    [StorageTypeInt]    = StorageTypeStack,
  },
  [StorageTypeXmmXmm] = {
    [StorageTypeXmm]    = StorageTypeStack,
    [StorageTypeInt]    = StorageTypeStack,
  },
  [StorageTypeXmmInt] = {
    [StorageTypeXmm]    = StorageTypeStack,
    [StorageTypeInt]    = StorageTypeStack,
  },
  [StorageTypeStack] = {
    [StorageTypeXmm]    = StorageTypeStack,
    [StorageTypeInt]    = StorageTypeStack,
  }
};

typedef struct StorageInfoAccumulator {
  uint32_t size;
  uint8_t  alignment;
  uint8_t  storageTypeCurrent;
  uint8_t  storageType;
  uint32_t totalSize;
} StorageInfoAccumulator;

static void
AccumulateInfo(StorageInfoAccumulator *this, GSObjCTypeInfo info)
{
  this->alignment = MAX(this->alignment, info.alignment);
  switch (*info.type)
    {
      case GSObjCTypeFloat:
      case GSObjCTypeDouble:
        break;
      case GSObjCTypeArrayBegin:
      case GSObjCTypeStructureBegin:
      case GSObjCTypeUnionBegin:
        break;
      case GSObjCTypeArrayEnd:
        this->storageTypeCurrent = StorageTypeInt;
        info.alignment = info.size = WordSize;
        break;
      case GSObjCTypeStructureEnd:
      case GSObjCTypeUnionEnd:
        info.size = GSObjCGetPadding(info.size, info.alignment);
        info.alignment = 1;
        break;
      default:
        this->storageTypeCurrent = StorageTypeInt;
    }
  size_t size = GSObjCPadSize(info.size, info.alignment);
  this->totalSize += size;
  this->size += size;
  if (this->size >= WordSize)
    {
      this->storageType = StorageTypeTransitions[this->storageType][this->storageTypeCurrent];
      this->size = 0;
      this->storageTypeCurrent = StorageTypeXmm;
    }
}

static const char *
GetStorageType(const char *type, uint32_t *storageType, uint32_t *size, uint8_t *alignment)
{
  StorageInfoAccumulator info = {0, 0, StorageTypeXmm, 0, 0};
  type = GSObjCParseTypeSpecification(type,
                                      (GSObjCTypeParserDelegate)&AccumulateInfo,
                                      &info, GSObjCReportArrayOnceMask);
  
  *storageType = info.storageType ? info.storageType : info.storageTypeCurrent;
  *size = info.totalSize;
  *alignment = info.alignment;
  
  /* skip offset */
  if (*type == '-' || *type == '+') ++type;
  while (*type >= '0' && *type <= '9')
    {
      ++type;
    }
  return type;
}

void
NSInvocationInvoke(id invocation);

void
NSInvocationReturn(id invocation);

void
NSInvocationForwardHandler();

void
NSInvocationForwardHandler_stret();

@implementation NSInvocation 

- (void)dealloc
{
  NSZoneFree([self zone], arguments);
  NSZoneFree([self zone], argumentInfo);
  if (ownResultBuffer)
    {
      NSZoneFree([self zone], result);
    }
  [signature release];
  [pool release];
}

- (id)init
{
  if (self = [super init])
    {
      retainTarget = NO;
      sendToSuper = NO;
      retainArguments = NO;
      retainedArguments = (uint32_t)0 - 1;
    }
  return self;
}

- (id)initWithObjCTypes:(const char *)types
{
  if (!(self = [self init]))
    {
      return self;
    }
  uint32_t regOffset = OffsetRegister, xmmOffset = OffsetFloat;
  uint32_t regBound = regOffset + WordSize * 6;
  uint32_t xmmBound = xmmOffset + FloatSize * 8;
  
  uint32_t storageType;
  uint32_t size;
  uint8_t  alignment;
  
  /* analyze return type */
  types = GetStorageType(types, &storageType, &size, &alignment);
  size = (uint32_t)GSObjCPadSize(size, alignment);
  if (storageType == StorageTypeStack)
    {
      regOffset += WordSize;
    }
  resultStorage = storageType;
  resultSize = size;
  
  ArgumentInfo offsets[MaxArgumentCount];
  uint8_t stackArgs[MaxArgumentCount], stackArgCount = 0;
  
  /* analyze arguments, build offset table */
  uint8_t  argIndex = 0;
  while (*types)
    {
      if (argIndex == MaxArgumentCount) /* WAT? */
        {
          abort();
        }
      
      types = GetStorageType(types, &storageType, &size, &alignment);
      size = (uint32_t)GSObjCPadSize(size, alignment); /* validate value? */
      
      BOOL regAvailable = regOffset < regBound;
      BOOL xmmAvailable = xmmOffset < xmmBound;
      
      /* I know this is terrifyingly ugly */
      SmallStructureInfo *info = (SmallStructureInfo *) &offsets[argIndex].offset;
      switch (storageType)
        {
          case StorageTypeXmm:
            if (xmmAvailable)
              {
                offsets[argIndex] = (ArgumentInfo){xmmOffset, size};
                xmmOffset += FloatSize;
                break;
              }
            goto UseStack;
          case StorageTypeInt:
            if (regAvailable)
              {
                offsets[argIndex] = (ArgumentInfo){regOffset, size};
                regOffset += WordSize;
                break;
              }
            goto UseStack;
          case StorageTypeIntInt:
            if (regOffset > regBound - WordSize * 2)
              {
                goto UseStack;
              }
            offsets[argIndex].size = 0;
            info->offset1 = regOffset;
            regOffset += WordSize;
            info->offset2 = regOffset;
            regOffset += WordSize;
            info->size2 = size - (info->size1 = WordSize);
            break;
          case StorageTypeIntXmm:
            if (!regAvailable || !xmmAvailable)
              {
                goto UseStack;
              }
            offsets[argIndex].size = 0;
            info->offset1 = regOffset;
            regOffset += WordSize;
            info->offset2 = xmmOffset;
            xmmOffset += FloatSize;
            info->size2 = size - (info->size1 = WordSize);
            break;
          case StorageTypeXmmXmm:
            if (xmmOffset > xmmBound - FloatSize * 2)
              {
                goto UseStack;
              }
            offsets[argIndex].size = 0;
            info->offset1 = xmmOffset;
            xmmOffset += FloatSize;
            info->offset2 = xmmOffset;
            xmmOffset += FloatSize;
            info->size2 = size - (info->size1 = WordSize);
            break;
          case StorageTypeXmmInt:
            if (!regAvailable || !xmmAvailable)
              {
                goto UseStack;
              }
            info->offset1 = xmmOffset;
            xmmOffset += FloatSize;
            info->offset2 = regOffset;
            regOffset += WordSize;
            info->size2 = size - (info->size1 = WordSize);
            break;
          case StorageTypeStack:
          UseStack:
            {
              offsets[argIndex] = (ArgumentInfo){0, size};
              stackArgs[stackArgCount] = argIndex;
              ++stackArgCount;
              break;
            }
        }
      
      ++argIndex;
    }
  
  argumentCount = argIndex;
  if (argumentCount)
    {
      argumentInfo = NSZoneCalloc([self zone], argumentCount, sizeof(ArgumentInfo));
      memcpy(argumentInfo, offsets, sizeof(ArgumentInfo) * argumentCount);
    }
  else
    {
      argumentInfo = NULL;
    }
  pool = [[NSMutableArray alloc] initWithCapacity:argumentCount];
  for (argIndex = 0; argIndex < argumentCount; ++argIndex) {
    [pool addObject:[NSNull null]];
  }
  
  stackSize = 0;
  for (uint8_t stackArgIndex = 0; stackArgIndex < stackArgCount; ++stackArgIndex)
    {
      argIndex = stackArgs[stackArgIndex];
      argumentInfo[argIndex].offset = OffsetStack + stackSize;
      argumentInfo[argIndex].size = offsets[argIndex].size;
      stackSize += GSObjCPadSize(offsets[argIndex].size, WordSize);
    }
  stackSize = (uint32_t)GSObjCPadSize(stackSize, StackAlignment);
  return self;
}

- (id)initWithMethodSignature:(NSMethodSignature *)aSignature arguments:(void *)frame
{
  if (self = [self initWithObjCTypes:[aSignature methodType]])
    {
      arguments = NSZoneMalloc([self zone], ArgumentListMinSize + stackSize);
      if (frame)
        {
          memcpy(arguments, frame, ArgumentListMinSize + stackSize);
        }
      if (!frame || resultStorage != StorageTypeStack)
        {
          result = NSZoneMalloc([self zone], MAX(resultSize, WordSize * 2));
          memset(result, 0, resultSize);
          ownResultBuffer = YES;
        }
      else
        {
          result = *(void **)(arguments + OffsetRegister);
          ownResultBuffer = NO;
        }
      if (resultStorage == StorageTypeStack)
        {
          *(void **)(arguments + OffsetRegister) = result;
          imp = &objc_msgSend_stret;
        }
      else
        {
          imp = &objc_msgSend;
        }
      signature = [aSignature retain];
    }
  return self;
}

- (id)initWithMethodSignature:(NSMethodSignature *)aSignature
{
  return [self initWithMethodSignature:aSignature arguments:NULL];
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature
{
  return [[[self alloc] initWithMethodSignature:signature arguments:NULL] autorelease];
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature
                                  arguments:(void *)arguments
{
  return [[[self alloc] initWithMethodSignature:signature arguments:arguments] autorelease];
}

- (void)getArgument:(void*)buffer atIndex:(NSInteger)index
{
  ArgumentInfo info = argumentInfo[index];
  if (info.size)
    {
      memcpy(buffer, arguments + info.offset, info.size);
    }
  else
    {
      SmallStructureInfo *smallInfo = (SmallStructureInfo *) &info.offset;
      memcpy(buffer, arguments + smallInfo->offset1, WordSize);
      memcpy(buffer + WordSize, arguments + smallInfo->offset2, smallInfo->size2);
    }
}

- (void)retainArgument:(void *)value atIndex:(NSInteger)index
{
  const char *type = [signature getArgumentTypeAtIndex:index];
  type = objc_skip_type_qualifiers(type);
  if (*type == '@')
    {
      [pool replaceObjectAtIndex:index withObject:*(id *)value];
    }
  retainedArguments |= (uint32_t)1 << index;
}

- (void)setArgument:(void *)value atIndex:(NSInteger)index
{
  if (retainArguments || (index == 0 && retainTarget))
    {
      [self retainArgument:value atIndex:index];
    }
  else
    {
      retainedArguments ^= (uint32_t)1 << index;
    }
  ArgumentInfo info = argumentInfo[index];
  if (info.size)
    {
      memcpy(arguments + info.offset, value, info.size);
    }
  else
    {
      SmallStructureInfo *smallInfo = (SmallStructureInfo *) &info.offset;
      memcpy(arguments + smallInfo->offset1, value, WordSize);
      memcpy(arguments + smallInfo->offset2, value + WordSize, smallInfo->size2);
    }
}

- (void)setArguments:(void *)arg1, ...
{
  va_list args;
  va_start(args, _cmd);
  for (uint8_t index = 0; index < argumentCount; ++index)
    {
      void *value = va_arg(args, void*);
      [self setArgument:value atIndex:index];
    }
  va_end(args);
}

- (void)setImplementation:(IMP)anImp
{
  imp = anImp;
}

- (void)invoke
{
  if (__builtin_expect(sendToSuper, NO))
    {
      void *oldImp = imp;
      imp = resultStorage == StorageTypeStack ? (void *)&objc_msgSendSuper_stret : (void *)&objc_msgSendSuper;
      
      id target = [self target];
      struct objc_super sup = {target, [target superclass]};
      void *ptr = &sup;
      [self setArgument:&ptr atIndex:0];
      
      NSInvocationInvoke(self);
      
      imp = oldImp;
      return;
    }
  
  NSInvocationInvoke(self);
}

- (void)returnResult
{
}

+ (void)load
{
  forwardSelector = @selector(forward::);
  objc_setForwardHandler(&NSInvocationForwardHandler, &NSInvocationForwardHandler_stret);
}

+ (void)initialize
{
//  class_replaceMethod(self, @selector(invoke), (IMP)&NSInvocationInvoke, "v@:");
  class_replaceMethod(self, @selector(returnResult), (IMP)&NSInvocationReturn, "v@:");
}

- (void)getReturnValue:(void*)buffer
{
  memcpy(buffer, result, resultSize);
}

- (void)setReturnValue:(void*)buffer
{
  memcpy(result, buffer, resultSize);
}

- (SEL)selector
{
  return *(SEL *)(arguments + argumentInfo[1].offset);
}

- (void)setSelector:(SEL)aSelector
{
  [self setArgument:&aSelector atIndex:1];
}

- (id)target
{
  return *(id *)(arguments + argumentInfo[0].offset);
}

- (void)setTarget:(id)anObject
{
  [self setArgument:&anObject atIndex:0];
}

- (BOOL)argumentsRetained
{
  return retainArguments;
}

- (void)retainArguments
{
  retainArguments = YES;
  if (retainedArguments != (uint32_t)0 - 1)
    {
      for (uint8_t index = 0; index < argumentCount; ++index) {
        uint32_t flag = (uint32_t)1 << index;
        if (!(retainedArguments & flag))
          {
            ArgumentInfo info = argumentInfo[index]; 
            if (info.size && info.size == WordSize)
              {
                [self retainArgument:(arguments + info.offset) atIndex:index];
              }
          }
      }
    }
}

- (void)invokeWithTarget:(id)anObject
{
  [self setArgument:&anObject atIndex:0];
  [self invoke];
}

- (NSMethodSignature *)methodSignature
{
  return signature;
}

- (BOOL)targetRetained
{
  return retainTarget;
}

- (void)retainArgumentsIncludingTarget:(BOOL)retainTargetFlag
{
  retainTarget = retainTargetFlag;
}

- (BOOL)sendsToSuper
{
  return sendToSuper;
}

- (void)setSendsToSuper:(BOOL)flag
{
  sendToSuper = flag;
}

/*
 * An internal method used to help NSConnections code invocations
 * to send over the wire 
 */
- (BOOL)encodeWithDistantCoder:(NSCoder *)coder passPointers:(BOOL)passp
{
  BOOL        outParameters = NO;
  const char	*type = [signature methodType];
  uint32_t    smallBuffer[4];
  
  [coder encodeValueOfObjCType:@encode(char*) at:&type];
  
  for (uint8_t argumentIndex = 0; argumentIndex < argumentCount; ++argumentIndex)
    {
      const char  *type = [signature getArgumentTypeAtIndex:argumentIndex];
      unsigned    qualifiers = objc_get_type_qualifiers(type);
      void        *datum;
      
      if (argumentInfo[argumentIndex].size != 0)
        {
          datum = arguments + argumentInfo[argumentIndex].offset;
        }
      else
        {
          [self getArgument:smallBuffer atIndex:argumentIndex];
          datum = smallBuffer;
        }
      
      /*
       * Decide how, (or whether or not), to encode the argument
       * depending on its FLAGS and TYPE.  Only the first two cases
       * involve parameters that may potentially be passed by
       * reference, and thus only the first two may change the value
       * of OUT_PARAMETERS.
       */
      switch (*type)
        {
          case GSObjCTypeId:
            if (qualifiers & GSObjCQualifierByCopyMask)
              {
                [coder encodeBycopyObject:*(id*)datum];
              }
            else if (qualifiers & GSObjCQualifierByRefMask)
              {
                [coder encodeByrefObject:*(id*)datum];
              }
            else
              {
                [coder encodeObject:*(id*)datum];
              }
            break;
          case GSObjCTypeCharPointer:
            /*
             * Handle a (char*) argument.
             * If the char* is qualified as an OUT parameter, or if it
             * not explicitly qualified as an IN parameter, then we will
             * have to get this char* again after the method is run,
             * because the method may have changed it.  Set
             * OUT_PARAMETERS accordingly.
             */
            if ((qualifiers & GSObjCQualifierOutMask) || !(qualifiers & GSObjCQualifierInMask))
              {
                outParameters = YES;
              }
            /*
             * If the char* is qualified as an IN parameter, or not
             * explicity qualified as an OUT parameter, then encode
             * it.
             */
            if ((qualifiers & GSObjCQualifierInMask) || !(qualifiers & GSObjCQualifierOutMask))
              {
                [coder encodeValueOfObjCType:type at:datum];
              }
            break;
          
          case GSObjCTypePointer:
            /*
             * If the pointer's value is qualified as an OUT parameter,
             * or if it not explicitly qualified as an IN parameter,
             * then we will have to get the value pointed to again after
             * the method is run, because the method may have changed
             * it.  Set OUT_PARAMETERS accordingly.
             */
            if ((qualifiers & GSObjCQualifierOutMask) || !(qualifiers & GSObjCQualifierInMask))
              {
                outParameters = YES;
              }
            if (passp)
              {
                if ((qualifiers & GSObjCQualifierInMask) || !(qualifiers & GSObjCQualifierOutMask))
                  {
                    [coder encodeValueOfObjCType:type at:datum];
                  }
              }
            else
              {
                /*
                 * Handle an argument that is a pointer to a non-char.  But
                 * (void*) and (anything**) is not allowed.
                 * The argument is a pointer to something; increment TYPE
                 * so we can see what it is a pointer to.
                 */
                type++;
                /*
                 * If the pointer's value is qualified as an IN parameter,
                 * or not explicity qualified as an OUT parameter, then
                 * encode it.
                 */
                if ((qualifiers & GSObjCQualifierInMask) || !(qualifiers & GSObjCQualifierOutMask))
                  {
                    [coder encodeValueOfObjCType:type at:*(void**)datum];
                  }
              }
            break;
          
          default:
            /* Handle arguments of all other types. */
            [coder encodeValueOfObjCType: type at: datum];
        }
    }
  
  /*
   * Return a BOOL indicating whether or not there are parameters that
   * were passed by reference; we will need to get those values again
   * after the method has finished executing because the execution of
   * the method may have changed them.
   */
  return outParameters;
}

@end

#import <Foundation/NSException.h>

static NSMethodSignature *
GSMethodSignatureForForwarding (id receiver, SEL forward, SEL sel)
{
  if (nil == receiver)
    {
      return nil;
    }
  
  NSMethodSignature *sig = nil;
  Class             cls  = object_getClass(receiver);
      
  if (class_respondsToSelector(cls, @selector(methodSignatureForSelector:)))
    {
      sig = [receiver methodSignatureForSelector: sel];
    }
  else
    {
        [NSException raise: NSInvalidArgumentException
                    format: @"%c[%s %s]: unrecognized selector sent to instance %p",
                            (class_isMetaClass(cls) ? '+' : '-'),
                            class_getName(cls), 
                            sel_getName(sel), 
                            receiver];
    }
  return sig;
}

#import <Foundation/NSObject.h>
#import <Foundation/NSProxy.h>

@interface NSObject (InvocationForwarding)
-(void)forward:(SEL)sel :(marg_list)args;
@end

@interface NSProxy (InvocationForwarding)
-(void)forward:(SEL)sel :(marg_list)args;
@end

@implementation NSObject (InvocationForwarding)

-(void)forward:(SEL)sel :(marg_list)args
{
  NSMethodSignature *signature = GSMethodSignatureForForwarding(self, _cmd, sel);
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature arguments:args];
  [self forwardInvocation:invocation];
  [invocation returnResult];
}

@end

@implementation NSProxy (InvocationForwarding)

-(void)forward:(SEL)sel :(marg_list)args
{
  NSMethodSignature *signature = GSMethodSignatureForForwarding(self, _cmd, sel);
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature arguments:args];
  [self forwardInvocation:invocation];
  [invocation returnResult];
}

@end

#endif