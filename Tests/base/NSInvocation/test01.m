#import "Testing.h"
#import "ObjectTesting.h"
#import "InvokeProxyProtocol.h"
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSProxy.h>

int main()
{ 
  NSAutoreleasePool   *arp = [NSAutoreleasePool new];
  NSInvocation *inv = nil; 
  NSObject <InvokeTarget>*tar;
  NSMethodSignature *sig;
  id ret;
  Class tClass = Nil;
  NSString *bundlePath;
  NSBundle *bundle; 
  NSUInteger retc; 
  bundlePath = [[[NSFileManager defaultManager] 
                              currentDirectoryPath] 
			       stringByAppendingPathComponent:@"Resources"];
  bundlePath = [[NSBundle bundleWithPath:bundlePath]
                  pathForResource:@"InvokeProxy"
	                   ofType:@"bundle"];
  bundle = [NSBundle bundleWithPath:bundlePath];
  PASS([bundle load],
       "loading resources from bundle");
  tClass = NSClassFromString(@"InvokeTarget");
   
  
  tar = [tClass new];
  
  /* Mac version of Apple's Foundation does not retain result objects */
  sig = [tar methodSignatureForSelector:@selector(retObject)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  retc = [[tar retObject] retainCount];
  [inv setSelector:@selector(retObject)];
  [inv invokeWithTarget:tar];
  if (nil == [NSGarbageCollector defaultCollector])
    {
      PASS(retc == [[tar retObject] retainCount], "Will not retain return value by default")
    }
  
  sig = [tar methodSignatureForSelector:@selector(loopObject:)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector:@selector(loopObject:)];
  [inv invokeWithTarget:tar];
  /* target is an argument at index zero, so it should be retained */
  retc = [tar retainCount];
  [inv retainArguments];
  if (nil == [NSGarbageCollector defaultCollector])
    {
        PASS(retc + 1 == [tar retainCount], "Will retain arguments, that are set already, after sending -[retainArguments]")
    }
  /* and now the same object is set at index two */
  retc = [tar retainCount];
  [inv setArgument:&tar atIndex:2];
  if (nil == [NSGarbageCollector defaultCollector])
    {
      PASS(retc + 1 == [tar retainCount], "Will retain new arguments, if -[retainArguments] is sent")
    }
  
  sig = [tar methodSignatureForSelector:@selector(loopObject:)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  retc = [tar retainCount];
  [inv setSelector:@selector(loopObject:)];
  [inv invokeWithTarget:tar];
  [inv setArgument:&tar atIndex:2];
  PASS(retc == [tar retainCount], "Will not retain arguments by default");
  
  sig = [tar methodSignatureForSelector:@selector(retObject)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector:@selector(retObject)];
  [inv invokeWithTarget:nil];
  [inv getReturnValue:&ret];
  PASS(ret == nil, "Check if nil target works");
  
  sig = [tar methodSignatureForSelector:@selector(returnIdButThrowException)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector:@selector(returnIdButThrowException)];
  PASS_EXCEPTION([inv invokeWithTarget:tar];, @"AnException", "Exception in invocation #1");
  /* Apple's Foundation does not throw expceptions in -[getReturnValue:] */
  BOOL raised = NO;
  NS_DURING
    [inv getReturnValue:&ret];
  NS_HANDLER
    raised = YES;
  NS_ENDHANDLER
  PASS(!raised, "Does not throw an exception while getting return value (test #1)");
 
  /* same as above but with a successful call first */
  sig = [tar methodSignatureForSelector:@selector(returnIdButThrowException)];
  inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector:@selector(retObject)];
  
  [inv invokeWithTarget:tar]; /* these two lines */
  [inv getReturnValue:&ret];
  
  [inv setSelector:@selector(returnIdButThrowException)];
  PASS_EXCEPTION([inv invokeWithTarget:tar];, @"AnException", "Exception in invocation #2");
  /* Apple's Foundation does not throw expceptions in -[getReturnValue:] */
  raised = NO;
  NS_DURING
    [inv getReturnValue:&ret];
  NS_HANDLER
    raised = YES;
  NS_ENDHANDLER
  PASS(!raised, "Does not throw an exception while getting return value (test #2)");
    
  
  [arp release]; arp = nil;
  return 0;
}
