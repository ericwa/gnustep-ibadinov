//
//  Test.m
//  butt
//
//  Created by Ibadinov Marat on 4/16/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//

#import "Testing.h"
#import <Foundation/Foundation.h>

#define AssignRetained(property, value) \
do {                                    \
    id backup = property;               \
    property = [value retain];          \
    [backup release];                   \
} while (0)


@interface Account : NSObject {
    NSUInteger uploaded;
    NSUInteger dowloaded;
}

- (NSUInteger)uploaded;
- (NSUInteger)downloaded;
- (NSUInteger)ratio;

- (void)setUploaded:(NSUInteger)uploadedDataSize;
- (void)setDownloaded:(NSUInteger)downloadedDataSize;

@end

@implementation Account

- (id)init
{
    if (self = [super init]) {
        uploaded = dowloaded = 0;
    }
    return self;
}

- (NSUInteger)uploaded
{
    return uploaded;
}

- (NSUInteger)downloaded
{
    return dowloaded;
}

- (NSUInteger)ratio
{
    static NSUInteger InitialThreshold = 4096;
    
    double ratio = (double)uploaded / (double)dowloaded;
    return dowloaded > InitialThreshold ? floor(ratio * 100) : 1;
}

- (void)setUploaded:(NSUInteger)uploadedDataSize
{
    [self willChangeValueForKey:@"uploaded"];
    uploaded = uploadedDataSize;
    [self didChangeValueForKey:@"uploaded"];
}

-(void)setDownloaded:(NSUInteger)downloadedDataSize
{
    [self willChangeValueForKey:@"downloaded"];
    dowloaded = downloadedDataSize;
    [self didChangeValueForKey:@"downloaded"];
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keyPaths = [super keyPathsForValuesAffectingValueForKey:key];
    if ([key isEqualToString:@"ratio"]) {
        NSArray *affectingKeys = [NSArray arrayWithObjects:@"uploaded", @"downloaded", nil];
        return [keyPaths setByAddingObjectsFromArray:affectingKeys];
    }
    return keyPaths;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:@"uploaded"] || [key isEqualToString:@"downloaded"]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

@end


@interface Person : NSObject {
    NSString    *firstName;
    NSString    *lastName;
    Account     *account;
}

- (id)initWithFirstName:(NSString *)aFirstName lastName:(NSString *)aLastName;

- (NSString *)firstName;
- (NSString *)lastName;
- (NSString *)fullName;

- (void)setFirstName:(NSString *)aName;
- (void)setLastName:(NSString *)aName;

- (Account *)account;
- (void)setAccount:(Account *)anAccount;

@end

@implementation Person

- (id)initWithFirstName:(NSString *)aFirstName lastName:(NSString *)aLastName
{
    if (self = [super init]) {
        AssignRetained(firstName, aFirstName);
        AssignRetained(lastName, aLastName);
        account = [[Account alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [lastName release];
    [firstName release];
    [super dealloc];
}

- (NSString *)firstName
{
    return firstName;
}

- (NSString *)lastName
{
    return lastName;
}

- (NSString *)fullName
{
    return [NSString stringWithFormat:@"%@ %@", firstName, lastName];
}

- (void)setFirstName:(NSString *)aName
{
    [self willChangeValueForKey:@"firstName"];
    AssignRetained(firstName, aName);
    [self didChangeValueForKey:@"firstName"];
}

- (void)setLastName:(NSString *)aName
{
    [self willChangeValueForKey:@"lastName"];
    AssignRetained(lastName, aName);
    [self didChangeValueForKey:@"lastName"];
}

- (Account *)account
{
    return account;
}

- (void)setAccount:(Account *)anAccount
{
    [self willChangeValueForKey:@"account"];
    AssignRetained(account, anAccount);
    [self didChangeValueForKey:@"account"];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %ld", [self fullName], (long)[account ratio]];
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keyPaths = [super keyPathsForValuesAffectingValueForKey:key];
    if ([key isEqualToString:@"fullName"]) {
        NSArray *affectingKeys = [NSArray arrayWithObjects:@"firstName", @"lastName", nil];
        keyPaths = [keyPaths setByAddingObjectsFromArray:affectingKeys];
    } 
    if ([key isEqualToString:@"description"]) {
        NSArray *affectingKeys = [NSArray arrayWithObjects:@"fullName", @"account.ratio", nil];
        keyPaths = [keyPaths setByAddingObjectsFromArray:affectingKeys];
    }
    return keyPaths;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:@"firstName"] || [key isEqualToString:@"lastName"] || [key isEqualToString:@"account"]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

@end


@interface Observer : NSObject {
    NSMutableArray *log;
}

- (NSArray *)log;
- (void)reset;

@end

@implementation Observer

- (id)init
{
    if (self = [super init]) {
        log = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [log dealloc];
    [super dealloc];
}

- (NSArray *)log
{
    return [[log copy] autorelease];
}

- (void)reset
{
    [log removeAllObjects];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSMutableDictionary *logEntry = [NSMutableDictionary new];    
    NSEnumerator *enumerator = [change keyEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject])) {
        id object = [change objectForKey:key];
        if ([object isKindOfClass:[NSNumber class]]) {
            [logEntry setObject:[(NSNumber *)object stringValue] forKey:key];
        } else {
            [logEntry setObject:object forKey:key];
        }
    }
    [logEntry setObject:keyPath forKey:@"path"];
    [log addObject:logEntry];
    [logEntry release];
}

@end


@interface RecursionObserver : Observer {
    NSObject    *value;
    NSString    *key;
    NSUInteger  depth;
}

- (id)initWithIntermediateValue:(NSObject *)aValue forKey:(NSString *)aKey;

@end

@implementation RecursionObserver

- (id)initWithIntermediateValue:(NSObject *)aValue forKey:(NSString *)aKey
{
    if (self = [super init]) {
        AssignRetained(value, aValue);
        AssignRetained(key, aKey);
        depth = 0;
    }
    return self;
}

- (void)dealloc
{
    [key release];
    [value release];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    [super observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context];
    if (++depth == 1) {
        [object setValue:value forKey:key];
    }
}

@end


@interface StackCurruptionObserver : Observer {
    NSString *path;
}

- (id)initWithKeyPath:(NSString *)aPath;

@end

@implementation StackCurruptionObserver

- (id)initWithKeyPath:(NSString *)aPath
{
    if (self = [super init]) {
        path = [aPath retain];
    }
    return self;
}

- (void)dealloc
{
    [path release];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
        [object didChangeValueForKey:path];
    }
}


@end


int main()
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *firstNameKey = @"firstName";
    NSString *lastNameKey = @"lastName";
    NSString *fullNameKey = @"fullName";
    NSString *descriptionKey = @"description";
    
    NSArray *log;
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew | NSKeyValueObservingOptionPrior;
    Person *observable = [[Person alloc] initWithFirstName:@"James" lastName:@"Watson"];
    
    
    RecursionObserver *recursionObserver = [[RecursionObserver alloc] initWithIntermediateValue:@"John" forKey:firstNameKey];
    [observable addObserver:recursionObserver forKeyPath:firstNameKey options:options context:NULL];
    [observable setValue:@"Emma" forKey:firstNameKey];
    [observable removeObserver:recursionObserver forKeyPath:firstNameKey];
    
    log = [NSArray arrayWithContentsOfFile:@"ChangeStack.plist"];
    PASS([[recursionObserver log] isEqual:log], "KVO maintains change stack");
    [recursionObserver release];
    
    
    [observable setValue:@"James" forKey:firstNameKey];
    StackCurruptionObserver *stackObserver = [[StackCurruptionObserver alloc] initWithKeyPath:lastNameKey];
    [observable addObserver:stackObserver forKeyPath:firstNameKey options:options context:NULL];
    [observable addObserver:stackObserver forKeyPath:lastNameKey options:options context:NULL];
    [observable setValue:@"Emma" forKey:firstNameKey];
    [observable removeObserver:stackObserver forKeyPath:lastNameKey];
    [observable removeObserver:stackObserver forKeyPath:firstNameKey];
        
    log = [NSArray arrayWithContentsOfFile:@"StackCorruption.plist"];
    PASS([[stackObserver log] isEqual:log], "KVO is robust against stack corruption");
    [stackObserver release];
    
    
    [observable setValue:@"John" forKey:firstNameKey];
    Observer *simpleObserver = [Observer new];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:NSKeyValueObservingOptionNew context:NULL];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:NSKeyValueObservingOptionNew context:NULL];
    [observable setValue:@"James" forKey:firstNameKey];    
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    
    log = [NSArray arrayWithContentsOfFile:@"Observance.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO sends notifications to each observance");
    
    
    [observable setValue:@"James" forKey:firstNameKey];
    [simpleObserver reset];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:NSKeyValueObservingOptionNew context:NULL];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:options context:NULL];
    [observable setValue:@"John" forKey:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    [observable setValue:@"Emma" forKey:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    
    log = [NSArray arrayWithContentsOfFile:@"ObservanceStack.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO processes observances as a stack");    
    
    
    [observable setValue:@"Emma" forKey:firstNameKey];
    [simpleObserver reset];
    [observable addObserver:simpleObserver forKeyPath:fullNameKey options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:fullNameKey options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew context:NULL];
    [observable setValue:@"John" forKey:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:fullNameKey];
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:fullNameKey];
    
    log = [NSArray arrayWithContentsOfFile:@"DependencyObservance.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO adds observances to affecting keys");
    
    
    [simpleObserver reset];
    [observable setValue:@"John" forKey:firstNameKey];
    [observable addObserver:simpleObserver forKeyPath:descriptionKey options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:fullNameKey options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:firstNameKey options:options context:NULL];
    [observable setValue:@"Emma" forKey:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:firstNameKey];
    [observable removeObserver:simpleObserver forKeyPath:fullNameKey];
    [observable removeObserver:simpleObserver forKeyPath:descriptionKey];
    
    log = [NSArray arrayWithContentsOfFile:@"ComplexDependency.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO supports complex dependencies");
    
    
    NSString *accountKey = @"account";
    NSString *uploadedKeyPath = @"account.uploaded";
    NSString *downloadedKeyPath = @"account.downloaded";
    NSString *ratioKeyPath = @"account.ratio";    
    
    
    [simpleObserver reset];
    [observable addObserver:simpleObserver forKeyPath:uploadedKeyPath options:options context:NULL];
    [observable setValue:[NSNumber numberWithInteger:1024] forKeyPath:uploadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:uploadedKeyPath];
    
    log = [NSArray arrayWithContentsOfFile:@"NestedProperty.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO supports nested properties");
    
    
    [simpleObserver reset];
    [observable setValue:[NSNumber numberWithInteger:4096] forKeyPath:uploadedKeyPath];
    [observable addObserver:simpleObserver forKeyPath:uploadedKeyPath options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:downloadedKeyPath options:options context:NULL];
    [observable setValue:[[Account new] autorelease] forKey:accountKey];
    [observable setValue:[NSNumber numberWithInteger:512] forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:uploadedKeyPath];
    
    log = [NSArray arrayWithContentsOfFile:@"NestedPropertyLevels.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO observes nested properties at all levels");
    
    
    [simpleObserver reset];
    [observable setValue:[NSNumber numberWithInteger:0] forKeyPath:downloadedKeyPath];
    [observable addObserver:simpleObserver forKeyPath:ratioKeyPath options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:uploadedKeyPath options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:downloadedKeyPath options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:ratioKeyPath options:options context:NULL];
    [observable setValue:[NSNumber numberWithInteger:1024] forKeyPath:uploadedKeyPath];
    [observable setValue:[NSNumber numberWithInteger:4096] forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:ratioKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:uploadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:ratioKeyPath];
    
    log = [NSArray arrayWithContentsOfFile:@"DependentNestedProperty.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO supports nested properties with dependencies");
    
    [simpleObserver reset];
    [observable setValue:@"James" forKey:firstNameKey];
    [observable setValue:[[Account new] autorelease] forKey:accountKey];
    [observable addObserver:simpleObserver forKeyPath:descriptionKey options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:ratioKeyPath options:options context:NULL];
    [observable addObserver:simpleObserver forKeyPath:downloadedKeyPath options:options context:NULL];
    [observable setValue:[NSNumber numberWithInt:8192] forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:downloadedKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:ratioKeyPath];
    [observable removeObserver:simpleObserver forKeyPath:descriptionKey];
    
    log = [NSArray arrayWithContentsOfFile:@"NestedPropertyDependency.plist"];
    PASS([[simpleObserver log] isEqual:log], "KVO supports dependencies on nested properties");
    [simpleObserver release];
    
    
    [observable release];
    [pool release];
}