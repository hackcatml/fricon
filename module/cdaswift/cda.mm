#import "cda.h"

@implementation AppUtils

static NSArray* apps;

+ (instancetype)sharedInstance
{
    static AppUtils *sharedInstance;
 
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppUtils alloc] init];
        apps = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    });
    return sharedInstance;
}

- (void) searchApp:(NSString *)searchTerm
{
    int i = 1;

    if([searchTerm isEqualToString:@"list"]){
        NSLog(@"");
        for(LSApplicationProxy* app in apps){
            NSString *identifier = app.bundleIdentifier;
            NSString *localizedName = app.localizedName;

            if([searchTerm isEqualToString:@"list"] && [identifier containsString:@"com.apple."]){
                continue;
            }
    
            NSLog(@"[%i] %@ (%@)", i, localizedName, identifier);
            i++;
        }
        NSLog(@"");
        return;
    }
}

- (NSString*)searchAppExecutable:(NSString*)bundleId
{
    int i = 1;
    for(LSApplicationProxy* app in apps){
        NSString *identifier = app.bundleIdentifier;
        if([identifier isEqualToString:bundleId]){
            return app.bundleExecutable;
        }
        i++;
    }
    return @"Nope";
}

- (NSString*)searchAppResourceDir:(NSString*)bundleId
{
    int i = 1;
    for(LSApplicationProxy* app in apps){
        NSString *identifier = app.bundleIdentifier;
        if([identifier isEqualToString:bundleId]){
            // .app 까지의 번들 디렉터리
            NSString* appResourceDir = app.bundleURL.path;
            // printf("appResourceDir: %s", [appResourceDir UTF8String]);
            return appResourceDir;
        }
        i++;
    }
    return @"Nope";
}

- (NSString*)searchAppBundleDir:(NSString*)bundleId
{
    int i = 1;
    for(LSApplicationProxy* app in apps){
        NSString* identifier = app.bundleIdentifier;
        if([identifier isEqualToString:bundleId]){
            NSString* appBundleDir = app.bundleContainerURL.path;
            return appBundleDir;
        }
        i++;
    }
    return @"Nope";
}

- (NSString*)searchAppDataDir:(NSString*)bundleId
{
    int i = 1;
    for(LSApplicationProxy* app in apps){
        NSString* identifier = app.bundleIdentifier;
        if([identifier isEqualToString:bundleId]){
            NSString* appDataDir = app.dataContainerURL.path;
            return appDataDir;
        }
        i++;
    }
    return @"Nope";
}

@end
