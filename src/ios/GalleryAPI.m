#import <Cordova/CDV.h>

#import "GalleryAPI.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

#define kDirectoryName @"mendr"

@interface GalleryAPI ()

@property int indexxx;
@property int videoCount;
@property int videoUrlCount;

// Allocated here for succinctness.
@property NSOperationQueue *concurrentThumbnailQueue;
@property NSOperationQueue *concurrentVideoQueue;
@property AVPlayer *avPlayer;
@property AVPlayerLayer *avPlayerLayer;
@property NSString *avPlayerStoredState;
@property AVPlayerViewController *avPlayerCtrl;

@end

@implementation GalleryAPI

- (void) checkPermission:(CDVInvokedUrlCommand*)command {
    dispatch_async(dispatch_get_main_queue(), ^(void){
        if(!self.avPlayerCtrl){
            CGFloat topPadding = 0.0;
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                topPadding = window.safeAreaInsets.top;
            }
            topPadding = topPadding + 45;
            CGFloat viewWidth = [[UIScreen mainScreen]bounds].size.width / 4 * 3;
            CGFloat viewHeight = viewWidth * 9 / 16 + 30;
            __weak GalleryAPI* weakSelf = self;
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            UIView *floatingView = [[UIView alloc] initWithFrame:CGRectMake(0,topPadding,viewWidth,viewHeight)];
    //                        self.avPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.avPlayer];
    //                        self.avPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    //                        self.avPlayerLayer.frame = extraView.bounds;
    //                        [extraView.layer addSublayer:self.avPlayerLayer];
            self.avPlayerCtrl = [[AVPlayerViewController alloc] init];
            self.avPlayerCtrl.view.frame = floatingView.frame;
            self.avPlayerCtrl.view.hidden = YES;
            self.avPlayerCtrl.delegate = weakSelf;
            self.avPlayerCtrl.showsPlaybackControls = TRUE;
    //                        [extraView addSubview:avPlayerCtrl.view];
            [self.viewController addChildViewController:self.avPlayerCtrl];
            [self.viewController.view addSubview:self.avPlayerCtrl.view];
            
        }
    });
    
    [self.commandDelegate runInBackground:^{
        __block NSDictionary *result;
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            // Access has been granted.
            result = @{@"success":@(true), @"message":@"Authorized"};
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result]
                                        callbackId:command.callbackId];
        }

        else if (status == PHAuthorizationStatusDenied) {
            // Access has been denied.
            result = @{@"success":@(false), @"message":@"Denied"};
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result]
                                        callbackId:command.callbackId];
        }

        else if (status == PHAuthorizationStatusNotDetermined) {
            // Access has not been determined.
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {

                if (status == PHAuthorizationStatusAuthorized) {
                    // Access has been granted.
                    result = @{@"success":@(true), @"message":@"Authorized"};
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result]
                                                callbackId:command.callbackId];
                }

                else {
                    // Access has been denied.
                    result = @{@"success":@(false), @"message":@"Denied"};
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result]
                                                callbackId:command.callbackId];
                }
            }];
        }

        else if (status == PHAuthorizationStatusRestricted) {
            // Restricted access - normally won't happen.
            result = @{@"success":@(false), @"message":@"Restricted"};
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result]
                                        callbackId:command.callbackId];
        }
    }];
}

- (void)getAlbums:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* subtypes = [GalleryAPI subtypes];
        __block NSMutableArray* albums = [[NSMutableArray alloc] init];
        __block NSDictionary* cameraRoll;

        NSArray* collectionTypes = @[
                                     @{ @"title" : @"smart",
                                        @"type" : [NSNumber numberWithInteger:PHAssetCollectionTypeSmartAlbum] },
                                     @{ @"title" : @"album",
                                        @"type" : [NSNumber numberWithInteger:PHAssetCollectionTypeAlbum] }
                                     ];

        for (NSDictionary* collectionType in collectionTypes) {
            [[PHAssetCollection fetchAssetCollectionsWithType:[collectionType[@"type"] integerValue] subtype:PHAssetCollectionSubtypeAny options:nil] enumerateObjectsUsingBlock:^(PHAssetCollection* collection, NSUInteger idx, BOOL* stop) {
                if (collection != nil && collection.localizedTitle != nil && collection.localIdentifier != nil && ([subtypes.allKeys indexOfObject:@(collection.assetCollectionSubtype)] != NSNotFound)) {
                    PHFetchResult* result = [PHAsset fetchAssetsInAssetCollection:collection
                                                                          options:nil];
                    if (result.count > 0) {
                        if ([collection.localizedTitle isEqualToString:@"Camera Roll"] && collection.assetCollectionType == PHAssetCollectionTypeSmartAlbum) {
                            cameraRoll = @{
                                           @"id" : collection.localIdentifier,
                                           @"title" : collection.localizedTitle,
                                           @"type" : subtypes[@(collection.assetCollectionSubtype)],
                                           @"assets" : [NSString stringWithFormat:@"%ld", (long)collection.estimatedAssetCount]
                                           };
                            
                        }
                        else {
                            [albums addObject:@{
                                                @"id" : collection.localIdentifier,
                                                @"title" : collection.localizedTitle,
                                                @"type" : subtypes[@(collection.assetCollectionSubtype)],
                                                @"assets" : [NSString stringWithFormat:@"%ld", (long)collection.estimatedAssetCount]
                                                }];
                        }
                    }
                }
            }];
        }

        if (cameraRoll)
            [albums insertObject:cameraRoll atIndex:0];

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:albums];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getMedia:(CDVInvokedUrlCommand*)command
{
    [self initConcurrent];
    [self.commandDelegate runInBackground:^{
        NSDictionary* subtypes = [GalleryAPI subtypes];
        NSDictionary* album = [command argumentAtIndex:0];
        __block NSMutableArray* assets = [[NSMutableArray alloc] init];
        __block PHImageRequestOptions* options = [[PHImageRequestOptions alloc] init];
        options.synchronous = YES;
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        options.networkAccessAllowed = true;

        PHFetchResult* collections = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[ album[@"id"] ]
                                                                                          options:nil];
        self.videoCount = 0;
        self.videoUrlCount = 0;
        
        if (collections && collections.count > 0) {
            PHAssetCollection* collection = collections[0];
            [[PHAsset fetchAssetsInAssetCollection:collection
                                           options:nil] enumerateObjectsUsingBlock:^(PHAsset* obj, NSUInteger idx, BOOL* stop) {
                if (obj.mediaType == PHAssetMediaTypeImage){
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    NSString *creationDate = [formatter stringFromDate:obj.creationDate];
                    NSString *modificationDate = [formatter stringFromDate:obj.modificationDate];
                    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary: @{
                       @"albumId" : album[@"id"]
                    }];
                    result[@"id"] = obj.localIdentifier;
                    result[@"title"] = @"";
                    result[@"orientation"] = @"up";
                    result[@"lat"] = @4;
                    result[@"lng"] = @5;
                    result[@"width"] = [NSNumber numberWithFloat:obj.pixelWidth];
                    result[@"height"] = [NSNumber numberWithFloat:obj.pixelHeight];
                    result[@"size"] = @0;
                    result[@"data"] = @"";
                    result[@"thumbnail"] = @"";
                    result[@"error"] = @"false";
                    result[@"createDate"] = creationDate;
                    result[@"modificationDate"] = modificationDate;
                    result[@"type"] = subtypes[@(collection.assetCollectionSubtype)];
                    result[@"fileType"] = @"photo";
                    result[@"fileTime"] =  [NSString stringWithFormat: @"%f", obj.duration];
                    [assets addObject:result];
                    
                } else if (obj.mediaType == PHAssetMediaTypeVideo){
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    NSString *creationDate = [formatter stringFromDate:obj.creationDate];
                    NSString *modificationDate = [formatter stringFromDate:obj.modificationDate];
                    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary: @{
                       @"albumId" : album[@"id"]
                    }];
                    
                    result[@"id"] = obj.localIdentifier;
                    result[@"title"] = @"";
                    result[@"orientation"] = @"up";
                    result[@"lat"] = @4;
                    result[@"lng"] = @5;
                    result[@"width"] = [NSNumber numberWithFloat:obj.pixelWidth];
                    result[@"height"] = [NSNumber numberWithFloat:obj.pixelHeight];
                    result[@"size"] = @0;
                    result[@"data"] = @"";
                    result[@"thumbnail"] = @"";
                    result[@"error"] = @"false";
                    result[@"createDate"] = creationDate;
                    result[@"modificationDate"] = modificationDate;
                    result[@"type"] = subtypes[@(collection.assetCollectionSubtype)];
                    result[@"fileType"] = @"video";
                    result[@"fileTime"] =  [NSString stringWithFormat: @"%f", obj.duration];
                    [assets addObject:result];
                    
                    
                }
            }];
        }
        
        NSArray* reversedAssests = [[assets reverseObjectEnumerator] allObjects];
        
        if ([album[@"method"] isEqualToString:@"generateThumbnails"]){
            for (int i=0; i < reversedAssests.count; i++){
                NSMutableDictionary *reversedAsset = [reversedAssests objectAtIndex:i];
                [self.concurrentThumbnailQueue addOperationWithBlock:^{
                    [self getMediaThumbnailInternal: reversedAsset atIndex:i withTotal:reversedAssests.count withCallbackId:command.callbackId];
                }];
                
//                if(i == reversedAssests.count - 1){
//                    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"done"];
//                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
//                }
            }
        } else {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:reversedAssests];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        
        
    }];
}

- (void)getMediaThumbnail:(CDVInvokedUrlCommand*)command
{
    [self initConcurrent];
    [self.commandDelegate runInBackground:^{
        PHImageRequestOptions* options = [PHImageRequestOptions new];
        options.synchronous = YES;
//        options.resizeMode = PHImageRequestOptionsResizeModeNone;
//        options.resizeMode = PHImageRequestOptionsResizeModeExact;
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        options.networkAccessAllowed = false;
//        options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
        
        NSMutableDictionary* media = [command argumentAtIndex:0];
        NSString* imageId = [media[@"id"] stringByReplacingOccurrencesOfString:@"/" withString:@"^"];
//        NSString* docsPath = [NSTemporaryDirectory() stringByStandardizingPath];
        NSArray * paths2 = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString * docsPath = [paths2 lastObject];
        NSString* thumbnailPath = [NSString stringWithFormat:@"%@/%@_mthumb.png", docsPath, imageId];

        NSFileManager* fileMgr = [[NSFileManager alloc] init];
        NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
        CGFloat screenWidth = [[UIScreen mainScreen]bounds].size.width;
        CGFloat scale = 2;
        if (screenWidth > 700) {
            scale = 1.5;
        }
        CGSize imageSize = CGSizeMake(systemVersion.floatValue < 12.0 ? 50: 300, systemVersion.floatValue < 12.0 ? 50: 300);

        if ([fileMgr fileExistsAtPath:thumbnailPath]){
//            NSLog(@"file exist");
            if ([media[@"method"] isEqualToString:@"getUrl"]){
                media[@"error"] = @"true";
                PHFetchResult* assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[media[@"id"]] options:nil];
                if (assets && assets.count > 0) {
                    media[@"error"] = @"false";
                    if ([media[@"fileType"] isEqualToString:@"video"]){
                        [self processVideo:assets[0] withMedia:media withFileMgr:fileMgr withCallBackId:command.callbackId];
                    }
                }
            }
            
        } else {
//            NSLog(@"file doesn't exist");
            media[@"error"] = @"true";
            PHFetchResult* assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[ media[@"id"] ] options:nil];
            
            if (assets && assets.count > 0) {
                    [[PHImageManager defaultManager] requestImageForAsset:assets[0]
                                                               targetSize:imageSize
                                                              contentMode:PHImageContentModeAspectFit
                                                                  options:options
                                                            resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
                                                                if (result) {
                                                                    [self.concurrentThumbnailQueue addOperationWithBlock:^(void){
                                                                        NSError* err = nil;
                                                                        if ([UIImageJPEGRepresentation(result, .6) writeToFile:thumbnailPath
                                                                            options:NSAtomicWrite
                                                                             error:&err])
                                                                            media[@"error"] = @"false";
                                                                        else {
                                                                            if (err) {
                                                                                media[@"thumbnail"] = @"";
                                                                                NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                            }
                                                                        }
                                                                    }];
                                                                    if([media[@"fileType"] isEqualToString:@"video"]){
                                                                        [self.concurrentVideoQueue addOperationWithBlock:^(void){
                                                                            [self processVideo:assets[0] withMedia:media withFileMgr:fileMgr withCallBackId:command.callbackId];
                                                                        }];
                                                                    }
                                                                }
                                                            }];
                
            }
            else {
                if ([media[@"type"] isEqualToString:@"PHAssetCollectionSubtypeAlbumMyPhotoStream"]) {
                    
                    [[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                              subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream
                                                              options:nil] enumerateObjectsUsingBlock:^(PHAssetCollection* collection, NSUInteger idx, BOOL* stop) {
                        if (collection != nil && collection.localizedTitle != nil && collection.localIdentifier != nil) {
                            [[PHAsset fetchAssetsInAssetCollection:collection
                                                           options:nil] enumerateObjectsUsingBlock:^(PHAsset* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
                                if ([obj.localIdentifier isEqualToString:media[@"id"]]) {
                                    [[PHImageManager defaultManager] requestImageForAsset:obj
                                                                               targetSize:imageSize
                                                                              contentMode:PHImageContentModeAspectFill
                                                                                  options:options
                                                                            resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
                                                                                if (result) {
                                                                                    NSError* err = nil;
                                                                                    if ([UIImagePNGRepresentation(result) writeToFile:thumbnailPath
                                                                                                                              options:NSAtomicWrite
                                                                                                                                error:&err])
                                                                                        media[@"error"] = @"false";
                                                                                    else {
                                                                                        if (err) {
                                                                                            media[@"thumbnail"] = @"";
                                                                                            NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }];
                                    if ([media[@"fileType"] isEqualToString:@"video"]){
                                        if ([media[@"fileType"] isEqualToString:@"video"]){
                                            [self processVideo:obj withMedia:media withFileMgr:fileMgr withCallBackId:command.callbackId];
                                        }
                                    }
                                }
                            }];
                        }
                    }];
                }
            }
        }
        
        if (![media[@"method"] isEqualToString:@"getUrl"]){
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:media];

            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (bool)getMediaThumbnailInternal: (NSMutableDictionary *)media atIndex:(int) index withTotal:(long)total withCallbackId:(NSString *)callbackId
{
    [self initConcurrent];
    PHImageRequestOptions* options = [PHImageRequestOptions new];
    options.synchronous = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.networkAccessAllowed = false;
    
//        NSMutableDictionary* media = [command argumentAtIndex:0];
    NSString* imageId = [media[@"id"] stringByReplacingOccurrencesOfString:@"/" withString:@"^"];
//        NSString* docsPath = [NSTemporaryDirectory() stringByStandardizingPath];
    NSArray * paths2 = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString * docsPath = [paths2 lastObject];
    NSString* thumbnailPath = [NSString stringWithFormat:@"%@/%@_mthumb.png", docsPath, imageId];

    NSFileManager* fileMgr = [[NSFileManager alloc] init];
//        NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    CGFloat screenWidth = [[UIScreen mainScreen]bounds].size.width;
    CGFloat scale = 2;
    if (screenWidth > 700) {
        scale = 1.5;
    }
    CGSize imageSize = CGSizeMake(screenWidth/3*scale, screenWidth/3*scale);
//        CGSize imageSize = CGSizeMake(systemVersion.floatValue < 12.0 ? 50: screenWidth/3*scale, systemVersion.floatValue < 12.0 ? 50: screenWidth/3*scale);

    if ([fileMgr fileExistsAtPath:thumbnailPath]){
        NSLog(@"File exists");
    } else {
        NSLog(@"File not exists");
        media[@"error"] = @"true";
        PHFetchResult* assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[ media[@"id"] ] options:nil];
        
        if (assets && assets.count > 0) {
//                [self.concurrentThumbnailQueue addOperationWithBlock:^(void){//  Set up a semaphore for the completion handler and progress timer
//                dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);
//                __block bool flag = YES;
                
                void (^completionHandler)(UIImage* _Nullable result, NSDictionary* _Nullable info) = ^(UIImage* _Nullable result, NSDictionary* _Nullable info)
                {
                    if (result) {
                        NSError *err = nil;
                        if ([UIImageJPEGRepresentation(result, .6) writeToFile:thumbnailPath
                            options:NSAtomicWrite
                             error:&err])
                            media[@"error"] = @"false";
                        else {
                            if (err) {
                                media[@"thumbnail"] = @"";
                                NSLog(@"Error saving image: %@", [err localizedDescription]);
                            }
                        }
                        NSLog(@"generating index %d", index);
//                        flag = NO;
//                        dispatch_semaphore_signal(sessionWaitSemaphore);
//                        if((index + 1) % 8 == 0){
//                            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"done"];
//                            [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
//                        }
                        if(index < 10){
                            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"done"];
                            [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                        }
                        
                    }
                };
                [[PHImageManager defaultManager] requestImageForAsset:assets[0]
                                                           targetSize:imageSize
                                                          contentMode:PHImageContentModeAspectFit
                                                              options:options
                                                        resultHandler:completionHandler];
//                do {
//                    dispatch_time_t dispatchTime = DISPATCH_TIME_FOREVER;  // if we dont want progress, we will wait until it finishes.
//                    dispatchTime = getDispatchTimeFromSeconds((float)1.0);
//                    dispatch_semaphore_wait(sessionWaitSemaphore, dispatchTime);
//                } while( flag );
//                }];
            return YES;
            
                
        }
        else {
            if ([media[@"type"] isEqualToString:@"PHAssetCollectionSubtypeAlbumMyPhotoStream"]) {
                
                [[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                          subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream
                                                          options:nil] enumerateObjectsUsingBlock:^(PHAssetCollection* collection, NSUInteger idx, BOOL* stop) {
                    if (collection != nil && collection.localizedTitle != nil && collection.localIdentifier != nil) {
                        [[PHAsset fetchAssetsInAssetCollection:collection
                                                       options:nil] enumerateObjectsUsingBlock:^(PHAsset* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
                            if ([obj.localIdentifier isEqualToString:media[@"id"]]) {
                                [[PHImageManager defaultManager] requestImageForAsset:obj
                                                                           targetSize:imageSize
                                                                          contentMode:PHImageContentModeAspectFill
                                                                              options:options
                                                                        resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
                                                                            if (result) {
                                                                                NSError* err = nil;
                                                                                if ([UIImagePNGRepresentation(result) writeToFile:thumbnailPath
                                                                                                                          options:NSAtomicWrite
                                                                                                                            error:&err])
                                                                                    media[@"error"] = @"false";
                                                                                else {
                                                                                    if (err) {
                                                                                        media[@"thumbnail"] = @"";
                                                                                        NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                                    }
                                                                                }
                                                                            }
                                                                        }];
                            }
                        }];
                    }
                }];
            }
        }
    }
    return NO;
    
}

- (void)initConcurrent
{
    if(self.concurrentThumbnailQueue.maxConcurrentOperationCount != 4){
        self.concurrentThumbnailQueue = [[NSOperationQueue alloc] init];
        self.concurrentThumbnailQueue.maxConcurrentOperationCount = 4;
    }
    
    if(self.concurrentVideoQueue.maxConcurrentOperationCount != 3){
        self.concurrentVideoQueue = [[NSOperationQueue alloc] init];
        self.concurrentVideoQueue.maxConcurrentOperationCount = 3;
    }
}

- (void)processVideo: (PHAsset *)avAsset withMedia:(NSMutableDictionary*)media withFileMgr:(NSFileManager *)fileMgr withCallBackId:(NSString *)callBackId
{
    [[PHImageManager defaultManager] requestAVAssetForVideo:avAsset options:nil resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info)
    {
        if ([asset isKindOfClass:[AVURLAsset class]])
        {
            NSURL *nsurl = [(AVURLAsset*)asset URL];
             // do what you want with it
            NSString *url = nsurl.absoluteURL.absoluteString;
            media[@"videoPath"] = url;
            media[@"error"] = @"false";
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:media];

            [self.commandDelegate sendPluginResult:pluginResult callbackId:callBackId];
        }
    }];
}

- (void)getHQImageData:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{

        PHImageRequestOptions* options = [PHImageRequestOptions new];
        options.synchronous = YES;
        options.resizeMode = PHImageRequestOptionsResizeModeNone;
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        options.networkAccessAllowed = true;

        NSString* mediaURL = nil;

        NSMutableDictionary* media = [command argumentAtIndex:0];

        NSString* docsPath = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:kDirectoryName];
        NSError* error;

        NSFileManager* fileMgr = [NSFileManager new];

        BOOL canCreateDirectory = false;

        if (![fileMgr fileExistsAtPath:docsPath])
            canCreateDirectory = true;

        BOOL canWriteFile = true;

        if (canCreateDirectory) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:docsPath
                                           withIntermediateDirectories:NO
                                                            attributes:nil
                                                                 error:&error]) {
                NSLog(@"Create directory error: %@", error);
                canWriteFile = false;
            }
        }

        if (canWriteFile) {
            NSString* imageId = [media[@"id"] stringByReplacingOccurrencesOfString:@"/" withString:@"^"];
            NSString* imagePath = [NSString stringWithFormat:@"%@/%@.jpg", docsPath, imageId];
            //                NSString* imagePath = [NSString stringWithFormat:@"%@/temp.png", docsPath];

            __block NSData* mediaData;
            mediaURL = imagePath;

            PHFetchResult* assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[ media[@"id"] ]
                                                                     options:nil];
            if (assets && assets.count > 0) {
                [[PHImageManager defaultManager] requestImageDataForAsset:assets[0]
                                                                  options:options
                                                            resultHandler:^(NSData* _Nullable imageData, NSString* _Nullable dataUTI, UIImageOrientation orientation, NSDictionary* _Nullable info) {
                                                                if (imageData) {
                                                                    //                                                                Processing Image Data if needed
                                                                    // Image must always be converted to JPEG to avoid reading HEIC files
                                                                    UIImage* image = [UIImage imageWithData:imageData];
                                                                    if (orientation != UIImageOrientationUp) {
                                                                        image = [self fixrotation:image];
                                                                    }
                                                                    mediaData = UIImageJPEGRepresentation(image, 1);

                                                                    //writing image to a file
                                                                    NSError* err = nil;
                                                                    if ([mediaData writeToFile:imagePath
                                                                                       options:NSAtomicWrite
                                                                                         error:&err]) {
                                                                        //                                                                    media[@"error"] = @"false";
                                                                    }
                                                                    else {
                                                                        if (err) {
                                                                            //                                                                        media[@"thumbnail"] = @"";
                                                                            NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                        }
                                                                    }
                                                                } else {
                                                                    @autoreleasepool {
                                                                        PHAsset *asset = assets[0];
                                                                        [[PHImageManager defaultManager] requestImageForAsset:asset
                                                                                                                   targetSize:CGSizeMake(asset.pixelWidth, asset.pixelHeight)
                                                                                                                  contentMode:PHImageContentModeAspectFit
                                                                                                                      options:options
                                                                                                                resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
                                                                                                                    if (result)
                                                                                                                        mediaData =UIImageJPEGRepresentation(result, 1);
                                                                                                                    NSError* err = nil;
                                                                                                                    if ([mediaData writeToFile:imagePath
                                                                                                                                       options:NSAtomicWrite
                                                                                                                                         error:&err]) {
                                                                                                                        //                                                                    media[@"error"] = @"false";
                                                                                                                    }
                                                                                                                    else {
                                                                                                                        if (err) {
                                                                                                                            //                                                                        media[@"thumbnail"] = @"";
                                                                                                                            NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                                                                        }
                                                                                                                    }
                                                                                                                }];
                                                                    };
                                                                }
                                                            }];

            }
            else {
                if ([media[@"type"] isEqualToString:@"PHAssetCollectionSubtypeAlbumMyPhotoStream"]) {

                    [[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                              subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream
                                                              options:nil] enumerateObjectsUsingBlock:^(PHAssetCollection* collection, NSUInteger idx, BOOL* stop) {
                        if (collection != nil && collection.localizedTitle != nil && collection.localIdentifier != nil) {
                            [[PHAsset fetchAssetsInAssetCollection:collection
                                                           options:nil] enumerateObjectsUsingBlock:^(PHAsset* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
                                if ([obj.localIdentifier isEqualToString:media[@"id"]]) {
                                    [[PHImageManager defaultManager] requestImageDataForAsset:obj
                                                                                      options:options
                                                                                resultHandler:^(NSData* _Nullable imageData, NSString* _Nullable dataUTI, UIImageOrientation orientation, NSDictionary* _Nullable info) {
                                                                                    if (imageData) {
                                                                                        //                                                                Processing Image Data if needed
                                                                                        // Image must always be converted to JPEG to avoid reading HEIC files
                                                                                        UIImage* image = [UIImage imageWithData:imageData];
                                                                                        if (orientation != UIImageOrientationUp) {
                                                                                            image = [self fixrotation:image];
                                                                                        }
                                                                                        mediaData = UIImageJPEGRepresentation(image, 1);

                                                                                        //writing image to a file
                                                                                        NSError* err = nil;
                                                                                        if ([mediaData writeToFile:imagePath
                                                                                                           options:NSAtomicWrite
                                                                                                             error:&err]) {
                                                                                            //                                                                    media[@"error"] = @"false";
                                                                                        }
                                                                                        else {
                                                                                            if (err) {
                                                                                                //                                                                        media[@"thumbnail"] = @"";
                                                                                                NSLog(@"Error saving image: %@", [err localizedDescription]);
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }];
                                }
                            }];
                        }
                    }];
                }
            }
        }

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:mediaURL ? CDVCommandStatus_OK : CDVCommandStatus_ERROR
                                                          messageAsString:mediaURL];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }];
}

-(void) controlVideoPlayer:(CDVInvokedUrlCommand*)command
{
    dispatch_async(dispatch_get_main_queue(), ^(void){
        if(!self.avPlayerCtrl){
            CGFloat topPadding = 0.0;
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                topPadding = window.safeAreaInsets.top;
            }
            topPadding = topPadding + 45;
            CGFloat viewWidth = [[UIScreen mainScreen]bounds].size.width / 4 * 3;
            CGFloat viewHeight = viewWidth * 9 / 16 + 30;
            __weak GalleryAPI* weakSelf = self;
                [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
                UIView *floatingView = [[UIView alloc] initWithFrame:CGRectMake(0,topPadding,viewWidth,viewHeight)];
                self.avPlayerCtrl = [[AVPlayerViewController alloc] init];
                self.avPlayerCtrl.view.frame = floatingView.frame;
                self.avPlayerCtrl.delegate = weakSelf;
                self.avPlayerCtrl.showsPlaybackControls = TRUE;
        //                        [extraView addSubview:avPlayerCtrl.view];
                [self.viewController addChildViewController:self.avPlayerCtrl];
                [self.viewController.view addSubview:self.avPlayerCtrl.view];
        }
        NSMutableDictionary* media = [command argumentAtIndex:0];
        
        if([media[@"getPlayState"] boolValue]){
            NSString *playState = @"paused";
            if ((self.avPlayer.rate != 0) && (self.avPlayer.error == nil)) {
                // player is playing
                playState = @"playing";
            }
            if (self.avPlayerCtrl.view.hidden){
                playState = @"hidden";
            }
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsString:playState];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        if([media[@"pause"] boolValue]){
            [self.avPlayer pause];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsString:@"Video paused"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        } else if ([media[@"play"] boolValue]){
            [self.avPlayer play];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsString:@"Video play"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        if([media[@"hide"] boolValue]){
            self.avPlayerCtrl.view.hidden = YES;
            [self.avPlayer pause];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsString:@"Video play hidden"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        } else {
            if(media[@"id"]){
                PHFetchResult* assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[ media[@"id"] ] options:nil];
                if (assets && assets.count > 0) {
                    [[PHImageManager defaultManager] requestAVAssetForVideo:assets[0] options:nil resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info)
                    {
                        if ([asset isKindOfClass:[AVURLAsset class]])
                        {
                            NSURL *nsurl = [(AVURLAsset*)asset URL];
                            dispatch_async(dispatch_get_main_queue(), ^(void){
                                self.avPlayer = [AVPlayer playerWithURL:nsurl];
                                self.avPlayerCtrl.player = self.avPlayer;
//                                [self.avPlayer seekToTime:storedPlaybackTime];
                                if([media[@"loadonly"] boolValue]){
                                    self.avPlayerCtrl.view.hidden = YES;
                                } else {
                                    self.avPlayerCtrl.view.hidden = NO;
                                    [self.avPlayer play];
                                }
                                
                            });
                        }
                    }];
                }
            } else {
                self.avPlayerCtrl.view.hidden = NO;
                [self.avPlayer play];
            }
        }
    });
}

+ (NSDictionary*)subtypes
{
    NSDictionary* subtypes = @{ @(PHAssetCollectionSubtypeAlbumRegular) : @"PHAssetCollectionSubtypeAlbumRegular",
                                @(PHAssetCollectionSubtypeAlbumImported) : @"PHAssetCollectionSubtypeAlbumImported",
//                                @(PHAssetCollectionSubtypeAlbumMyPhotoStream) : @"PHAssetCollectionSubtypeAlbumMyPhotoStream",
//                                @(PHAssetCollectionSubtypeAlbumCloudShared) : @"PHAssetCollectionSubtypeAlbumCloudShared",
                                @(PHAssetCollectionSubtypeSmartAlbumFavorites) : @"PHAssetCollectionSubtypeSmartAlbumFavorites",
                                @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded) : @"PHAssetCollectionSubtypeSmartAlbumRecentlyAdded",
                                @(PHAssetCollectionSubtypeSmartAlbumUserLibrary) : @"PHAssetCollectionSubtypeSmartAlbumUserLibrary",
                                @(PHAssetCollectionSubtypeSmartAlbumSelfPortraits) : @"PHAssetCollectionSubtypeSmartAlbumSelfPortraits",
                                @(PHAssetCollectionSubtypeSmartAlbumScreenshots) : @"PHAssetCollectionSubtypeSmartAlbumScreenshots",
                                };
    return subtypes;
}



// modified version of http://stackoverflow.com/a/21230645/1673842
- (UIImage *)generateThumbnailImage: (NSURL *)url atSzie: (CGSize)imageSize withMaxRetry: (int)totalRetried atAssetId: (NSString *)assetId
{
//    NSURL *url = [NSURL fileURLWithPath:srcVideoPath];
    CMTime time = CMTimeMake(1, 1);

    AVAsset *asset = [AVAsset assetWithURL:url];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.requestedTimeToleranceAfter = kCMTimeZero; // needed to get a precise time (http://stackoverflow.com/questions/5825990/i-cannot-get-a-precise-cmtime-for-generating-still-image-from-1-8-second-video)
    imageGenerator.requestedTimeToleranceBefore = kCMTimeZero; // ^^
    imageGenerator.appliesPreferredTrackTransform = YES; // crucial to have the right orientation for the image (http://stackoverflow.com/questions/9145968/getting-video-snapshot-for-thumbnail)
    imageGenerator.maximumSize = imageSize;
    NSError *error = NULL;
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:&error];
    if(error){
        @try{
            NSLog(@"截取视频 %@ 缩略图时发生错误，错误信息：%@", url.absoluteString, error);
            [NSThread sleepForTimeInterval: .5];
            if(totalRetried > 0){
                totalRetried = totalRetried - 1;
                return [self generateThumbnailImage:url atSzie:imageSize withMaxRetry:totalRetried atAssetId:assetId];
                
            } else if (totalRetried != -99) {
                NSString *root = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
                NSString *tempDir = [root stringByAppendingString:@"/com.photo.video/temp"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:tempDir isDirectory:nil]) {
                    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
                }
                NSString *outputvideoName = assetId;
                outputvideoName = [outputvideoName stringByReplacingOccurrencesOfString:@"/" withString:@"-"] ;
                NSString *myPathDocs =  [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"mergeSlowMoVideo-%@.mp4",outputvideoName]];
                NSURL *outUrl = [NSURL fileURLWithPath:myPathDocs];
                AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
                exporter.outputURL = outUrl;
                exporter.outputFileType = AVFileTypeMPEG4;
                exporter.shouldOptimizeForNetworkUse = YES;
                [self.concurrentVideoQueue addOperationWithBlock:^{
                    [exporter exportAsynchronouslyWithCompletionHandler:^{
                        if (exporter.status == AVAssetExportSessionStatusCompleted) {
                            NSURL *exporterURL = exporter.outputURL;
                            UIImage *thumbnail = [self generateThumbnailImage:exporterURL atSzie:imageSize withMaxRetry:-99 atAssetId:assetId];
                            if (thumbnail){
                                NSString* imageId = [assetId stringByReplacingOccurrencesOfString:@"/" withString:@"^"];
                                NSArray * paths2 = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                                NSString * docsPath = [paths2 lastObject];
                                NSString* thumbnailPath = [NSString stringWithFormat:@"%@/%@_mthumb.png", docsPath, imageId];
                                [UIImagePNGRepresentation(thumbnail) writeToFile:thumbnailPath options:NSAtomicWrite error:nil];
                            }
                        }
                    }];
                }];
            }
        }
        @catch(id err){
            
        }
        return NULL;
    } else {
        UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);  // CGImageRef won't be released by ARC
        return thumbnail;
    }
    
}

- (UIImage*)fixrotation:(UIImage*)image
{

    if (image.imageOrientation == UIImageOrientationUp)
        return image;
    CGAffineTransform transform = CGAffineTransformIdentity;

    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;

        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;

        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }

    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;

        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }

    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, image.size.width, image.size.height,
                                             CGImageGetBitsPerComponent(image.CGImage), 0,
                                             CGImageGetColorSpace(image.CGImage),
                                             CGImageGetBitmapInfo(image.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0, 0, image.size.height, image.size.width), image.CGImage);
            break;

        default:
            CGContextDrawImage(ctx, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
            break;
    }

    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage* img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

static dispatch_time_t getDispatchTimeFromSeconds(float seconds) {
    long long milliseconds = seconds * 1000.0;
    dispatch_time_t waitTime = dispatch_time( DISPATCH_TIME_NOW, 1000000LL * milliseconds );
    return waitTime;
}

+ (NSString*)cordovaVersion
{
    return CDV_VERSION;
}

@end
