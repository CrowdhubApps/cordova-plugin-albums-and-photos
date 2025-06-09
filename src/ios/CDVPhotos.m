#import "CDVPhotos.h"
#import <Photos/Photos.h>

@interface CDVPhotos ()
@property (nonatomic, strong, readonly) NSDateFormatter* dateFormat;
@property (nonatomic, strong, readonly) NSDictionary<NSString*, NSString*>* extType;
@property (nonatomic, strong, readonly) NSRegularExpression* extRegex;
@property (nonatomic, strong) CDVInvokedUrlCommand* photosCommand;
@end

@implementation CDVPhotos

NSString* const P_ID = @"id";
NSString* const P_NAME = @"name";
NSString* const P_WIDTH = @"width";
NSString* const P_HEIGHT = @"height";
NSString* const P_LAT = @"latitude";
NSString* const P_LON = @"longitude";
NSString* const P_DATE = @"date";
NSString* const P_TS = @"timestamp";
NSString* const P_TYPE = @"contentType";
NSString* const P_URI = @"uri";
NSString* const P_COUNT = @"count";

NSString* const P_SIZE = @"dimension";
NSString* const P_QUALITY = @"quality";
NSString* const P_AS_DATAURL = @"asDataUrl";

NSString* const P_C_MODE = @"collectionMode";
NSString* const P_C_MODE_ROLL = @"ROLL";
NSString* const P_C_MODE_SMART = @"SMART";
NSString* const P_C_MODE_ALBUMS = @"ALBUMS";
NSString* const P_C_MODE_MOMENTS = @"MOMENTS";

NSString* const P_LIST_OFFSET = @"offset";
NSString* const P_LIST_LIMIT = @"limit";
NSString* const P_LIST_INTERVAL = @"interval";

NSString* const T_DATA_URL = @"data:image/jpeg;base64,%@";
NSString* const T_DATE_FORMAT = @"YYYY-MM-dd\'T\'HH:mm:ssZZZZZ";
NSString* const T_EXT_PATTERN = @"^(.+)\\.([a-z]{3,4})$";

NSInteger const DEF_SIZE = 120;
NSInteger const DEF_QUALITY = 80;
NSString* const DEF_NAME = @"No Name";

NSString* const E_PERMISSION = @"Access to Photo Library permission required";
NSString* const E_COLLECTION_MODE = @"Unsupported collection mode";
NSString* const E_PHOTO_NO_DATA = @"Specified photo has no data";
NSString* const E_PHOTO_THUMB = @"Cannot get a thumbnail of photo";
NSString* const E_PHOTO_ID_UNDEF = @"Photo ID is undefined";
NSString* const E_PHOTO_ID_WRONG = @"Photo with specified ID wasn't found";
NSString* const E_PHOTO_NOT_IMAGE = @"Data with specified ID isn't an image";
NSString* const E_PHOTO_BUSY = @"Fetching of photo assets is in progress";

NSString* const S_SORT_TYPE = @"creationDate";

- (void) pluginInitialize {
    _dateFormat = [[NSDateFormatter alloc] init];
    [_dateFormat setDateFormat:T_DATE_FORMAT];

    _extType = @{@"JPG": @"image/jpeg",
                 @"JPEG": @"image/jpeg",
                 @"PNG": @"image/png",
                 @"GIF": @"image/gif",
                 @"TIF": @"image/tiff",
                 @"TIFF": @"image/tiff",
                 @"HEIC": @"image/jpeg",
				 @"MP4": @"video/mp4",
				 @"MOV": @"video/quicktime",
				 @"AVI": @"video/x-msvideo",
				 @"MPEG": @"video/mpeg",
				 @"MPG": @"video/mpeg",
				 @"MPEG-4": @"video/mp4",
				 @"M4V": @"video/mp4",
				 @"M4A": @"audio/mp4",
				 @"AAC": @"audio/mp4",
				 @"MP3": @"audio/mp3",
				 @"WAV": @"audio/wav",
				 @"WMA": @"audio/x-ms-wma"};

    _extRegex = [NSRegularExpression
                 regularExpressionWithPattern:T_EXT_PATTERN
                 options:NSRegularExpressionCaseInsensitive
                 + NSRegularExpressionDotMatchesLineSeparators
                 + NSRegularExpressionAnchorsMatchLines
                 error:NULL];
}

#pragma mark - Command implementations

- (void) collections:(CDVInvokedUrlCommand*)command {
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        NSDictionary* options = [weakSelf argOf:command atIndex:0 withDefault:@{}];
        
        PHFetchResult<PHCollection*>* fetchResultCollections
        = [weakSelf fetchCollections:options];
        if (fetchResultCollections == nil) {
            [weakSelf failure:command withMessage:E_COLLECTION_MODE];
            return;
        }
        NSMutableArray<PHCollection*>* array
        = [NSMutableArray arrayWithCapacity:fetchResultCollections.count];
        
        [fetchResultCollections enumerateObjectsUsingBlock:
        ^(PHCollection* _Nonnull collection, NSUInteger idx, BOOL* _Nonnull stop) {
            if ([collection isKindOfClass:PHCollectionList.class]) {
                //Skip album sub directories
                [array addObject:(PHAssetCollection*)collection];
            } else {
                [array addObject:(PHAssetCollection*)collection];
            }
        }];
        
        int assetCollectionCount = 0;
        
        for (PHCollection* collection in array) {
            if ([collection isKindOfClass:PHCollectionList.class] || !((PHAssetCollection*)collection).canContainAssets) {
                //Skip album sub directories
            } else {
                assetCollectionCount++;
            }
        }
        
        NSMutableArray<NSDictionary*>* result
        = [NSMutableArray arrayWithCapacity:assetCollectionCount];
        
        for (PHCollection* collection in array) {
            if ([collection isKindOfClass:PHCollectionList.class] || !((PHAssetCollection*)collection).canContainAssets) {
                //Skip album sub directories
            } else {
                PHAssetCollection* assetCollection = (PHAssetCollection*)collection;
                NSString* count = [@(assetCollection.estimatedAssetCount) stringValue];
                NSString* title = assetCollection.localizedTitle;
                if ([weakSelf isNull:assetCollection.localizedTitle]) {
                    title = DEF_NAME;
                }
                 NSMutableDictionary<NSString*, NSObject*>* collectionItem
                 = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    assetCollection.localIdentifier, P_ID,
                    title, P_NAME,
                    count, P_COUNT,
                    nil];

                 [result addObject:collectionItem];
            }
        }
        [weakSelf success:command withArray:result];
    }];
}

- (void) photos:(CDVInvokedUrlCommand*)command {
    if (![self isNull:self.photosCommand]) {
        [self failure:command withMessage:E_PHOTO_BUSY];
        return;
    }
    self.photosCommand = command;
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        NSArray* collectionIds = [weakSelf argOf:command atIndex:0 withDefault:nil];
        NSLog(@"photos: collectionIds=%@", collectionIds);
        
        NSMutableArray<NSDictionary*>* result = nil;
        
        if (collectionIds == nil || collectionIds.count == 0) {
            result = [weakSelf fetchAllImages];
        } else {
            PHFetchResult<PHAssetCollection*>* fetchResultAssetCollections = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:collectionIds
            options:nil];
            
            if (fetchResultAssetCollections == nil) {
                weakSelf.photosCommand = nil;
                [weakSelf failure:command withMessage:E_COLLECTION_MODE];
                return;
            }
            
            result = [weakSelf fetchImagesFromCollections:fetchResultAssetCollections];
        }
        
        weakSelf.photosCommand = nil;
        [weakSelf success:command withArray:result];
    }];
}

- (void) videos:(CDVInvokedUrlCommand*)command {
    if (![self isNull:self.photosCommand]) {
        [self failure:command withMessage:E_PHOTO_BUSY];
        return;
    }
    self.photosCommand = command;
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        NSArray* collectionIds = [weakSelf argOf:command atIndex:0 withDefault:nil];
        NSLog(@"videos: collectionIds=%@", collectionIds);
        
        NSMutableArray<NSDictionary*>* result = nil;
        
        if (collectionIds == nil || collectionIds.count == 0) {
            result = [weakSelf fetchAllVideos];
        } else {
            PHFetchResult<PHAssetCollection*>* fetchResultAssetCollections = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:collectionIds
            options:nil];
            
            if (fetchResultAssetCollections == nil) {
                weakSelf.photosCommand = nil;
                [weakSelf failure:command withMessage:E_COLLECTION_MODE];
                return;
            }
            
            result = [weakSelf fetchVideosFromCollections:fetchResultAssetCollections];
        }
        
        weakSelf.photosCommand = nil;
        [weakSelf success:command withArray:result];
    }];
}

- (void) thumbnail:(CDVInvokedUrlCommand*)command {
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        PHAsset* asset = [weakSelf assetByCommand:command];
        if (asset == nil) return;

        NSDictionary* options = [weakSelf argOf:command atIndex:1 withDefault:@{}];

        NSInteger size = [options[P_SIZE] integerValue];
        if (size <= 0) size = DEF_SIZE;
        NSInteger quality = [options[P_QUALITY] integerValue];
        if (quality <= 0) quality = DEF_QUALITY;
        BOOL asDataUrl = [options[P_AS_DATAURL] boolValue];

        if (asset.mediaType == PHAssetMediaTypeImage) {
            PHImageRequestOptions* reqOptions = [[PHImageRequestOptions alloc] init];
            reqOptions.resizeMode = PHImageRequestOptionsResizeModeExact;
            reqOptions.networkAccessAllowed = YES;
            reqOptions.synchronous = YES;
            reqOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

            [[PHImageManager defaultManager]
             requestImageForAsset:asset
             targetSize:CGSizeMake(size, size)
             contentMode:PHImageContentModeDefault
             options:reqOptions
             resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
                 NSError* error = info[PHImageErrorKey];
                 if (![weakSelf isNull:error]) {
                     [weakSelf failure:command withMessage:error.localizedDescription];
                     return;
                 }
                 if ([weakSelf isNull:result]) {
                     [weakSelf failure:command withMessage:E_PHOTO_NO_DATA];
                     return;
                 }
                 UIGraphicsBeginImageContext(result.size);
                 [result drawInRect:CGRectMake(0, 0, result.size.width, result.size.height)];
                 UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
                 UIGraphicsEndImageContext();
                 NSData* data = UIImageJPEGRepresentation(image, (CGFloat) quality / 100);
                 if ([weakSelf isNull:data]) {
                     [weakSelf failure:command withMessage:E_PHOTO_THUMB];
                     return;
                 }
                 if (asDataUrl) {
                     NSString* dataUrl = [NSString stringWithFormat:T_DATA_URL,
                                          [data base64EncodedStringWithOptions:0]];
                     [weakSelf success:command withMessage:dataUrl];
                 } else [weakSelf success:command withData:data];
             }];
        } else if (asset.mediaType == PHAssetMediaTypeVideo) {
            PHVideoRequestOptions* options = [[PHVideoRequestOptions alloc] init];
            options.networkAccessAllowed = YES;
            options.version = PHVideoRequestOptionsVersionOriginal;
            
            [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset* _Nullable avAsset, AVAudioMix* _Nullable audioMix, NSDictionary* _Nullable info) {
                if (![weakSelf isNull:info[PHImageErrorKey]]) {
                    [weakSelf failure:command withMessage:((NSError *)info[PHImageErrorKey]).localizedDescription];
                    return;
                }
                
                if ([weakSelf isNull:avAsset]) {
                    [weakSelf failure:command withMessage:@"Could not load video asset"];
                    return;
                }
                
                CGFloat videoWidth = asset.pixelWidth;
                CGFloat videoHeight = asset.pixelHeight;
                CGFloat targetWidth = size;
                CGFloat targetHeight = size;

                if (videoWidth > 0 && videoHeight > 0) {
                    CGFloat aspectRatio = videoWidth / videoHeight;
                    if (videoWidth > videoHeight) {
                        targetHeight = size / aspectRatio;
                    } else {
                        targetWidth = size * aspectRatio;
                    }
                }

                AVAssetImageGenerator* generator = [[AVAssetImageGenerator alloc] initWithAsset:avAsset];
                generator.appliesPreferredTrackTransform = YES;
                generator.maximumSize = CGSizeMake(targetWidth, targetHeight);
                
                CMTime time = CMTimeMake(0, 1);
                NSError* error = nil;
                CGImageRef cgImage = [generator copyCGImageAtTime:time actualTime:nil error:&error];
                
                if (error) {
                    [weakSelf failure:command withMessage:error.localizedDescription];
                    return;
                }
                
                if (cgImage == NULL) {
                    [weakSelf failure:command withMessage:@"Failed to generate video thumbnail"];
                    return;
                }
                
                UIImage* image = [UIImage imageWithCGImage:cgImage];
                CGImageRelease(cgImage);
                
                UIGraphicsBeginImageContext(CGSizeMake(targetWidth, targetHeight));
                [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
                UIImage* thumbnail = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                NSData* data = UIImageJPEGRepresentation(thumbnail, (CGFloat) quality / 100);
                if ([weakSelf isNull:data]) {
                    [weakSelf failure:command withMessage:E_PHOTO_THUMB];
                    return;
                }
                
                if (asDataUrl) {
                    NSString* dataUrl = [NSString stringWithFormat:T_DATA_URL,
                                         [data base64EncodedStringWithOptions:0]];
                    [weakSelf success:command withMessage:dataUrl];
                } else [weakSelf success:command withData:data];
            }];
        }
    }];
}

- (void) image:(CDVInvokedUrlCommand*)command {
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        PHAsset* asset = [weakSelf assetByCommand:command];
        if (asset == nil) return;

        PHImageRequestOptions* reqOptions = [[PHImageRequestOptions alloc] init];
        reqOptions.networkAccessAllowed = YES;
        reqOptions.progressHandler = ^(double progress,
                                       NSError* __nullable error,
                                       BOOL* stop,
                                       NSDictionary* __nullable info) {
            NSLog(@"progress: %.2f, info: %@", progress, info);
            if (![weakSelf isNull:error]) {
                NSLog(@"error: %@", error);
                *stop = YES;
            }
        };

        [[PHImageManager defaultManager]
         requestImageDataForAsset:asset
         options:reqOptions
         resultHandler:^(NSData* _Nullable imageData,
                         NSString* _Nullable dataUTI,
                         UIImageOrientation orientation,
                         NSDictionary* _Nullable info) {
             NSError* error = info[PHImageErrorKey];
             if (![weakSelf isNull:error]) {
                 [weakSelf failure:command withMessage:error.localizedDescription];
                 return;
             }
             if ([weakSelf isNull:imageData]) {
                 [weakSelf failure:command withMessage:E_PHOTO_NO_DATA];
                 return;
             }
             UIImage* image = [UIImage imageWithData:imageData];
             UIImage* imageOriented = [weakSelf rotateUIImage:image orientation:orientation];
             NSData* mediaData = UIImageJPEGRepresentation(imageOriented, 1);// only JPEG Representation
             [weakSelf success:command withData:mediaData];
         }];
    }];
}

- (UIImage*)rotateUIImage:(UIImage*)sourceImage orientation:(UIImageOrientation)orientation
{
    CGSize size = sourceImage.size;
    
    switch (orientation) {
        case UIImageOrientationDown:          // 180 deg rotation
        case UIImageOrientationLeft:          // 90 deg CCW
        case UIImageOrientationRight:         // 90 deg CW
            break ;
        case UIImageOrientationUp:            // default orientation
        case UIImageOrientationUpMirrored:    // as above but image mirrored along other axis. horizontal flip
        case UIImageOrientationDownMirrored:  // horizontal flip
        case UIImageOrientationLeftMirrored:  // vertical flip
        case UIImageOrientationRightMirrored: // vertical flip
            return sourceImage;
    }
    UIGraphicsBeginImageContext(CGSizeMake(size.width, size.height));
    [[UIImage imageWithCGImage:[sourceImage CGImage] scale:1.0 orientation:orientation] drawInRect:CGRectMake(0,0,size.width,size.height)];
    UIImage* newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return newImage;
}

- (void) video:(CDVInvokedUrlCommand*)command {
    CDVPhotos* __weak weakSelf = self;
    [self checkPermissionsOf:command andRun:^{
        PHAsset* asset = [weakSelf assetByCommand:command];
        if (asset == nil) return;

        if (asset.mediaType != PHAssetMediaTypeVideo) {
            [weakSelf failure:command withMessage:@"Asset is not a video"];
            return;
        }

        PHVideoRequestOptions* options = [[PHVideoRequestOptions alloc] init];
        options.networkAccessAllowed = YES;
        options.version = PHVideoRequestOptionsVersionOriginal; // Get original video

        [[PHImageManager defaultManager] requestExportSessionForVideo:asset 
                                                              options:options 
                                                         exportPreset:AVAssetExportPresetHighestQuality 
                                                        resultHandler:^(AVAssetExportSession * _Nullable exportSession, NSDictionary * _Nullable info) {
            if (![weakSelf isNull:info[PHImageErrorKey]]) {
                [weakSelf failure:command withMessage:((NSError *)info[PHImageErrorKey]).localizedDescription];
                return;
            }

            if (exportSession == nil) {
                [weakSelf failure:command withMessage:@"Could not create export session for video asset"];
                return;
            }

            NSString* outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov", asset.localIdentifier]];
            NSURL* outputURL = [NSURL fileURLWithPath:outputFilePath];

            // Remove existing file if any
            NSFileManager* fileManager = [NSFileManager defaultManager];
            if ([fileManager fileExistsAtPath:outputFilePath]) {
                NSError* error = nil;
                [fileManager removeItemAtPath:outputFilePath error:&error];
                if (error) {
                    [weakSelf failure:command withMessage:[NSString stringWithFormat:@"Could not remove existing temp file: %@", error.localizedDescription]];
                    return;
                }
            }
            
            exportSession.outputURL = outputURL;
            // Try to determine a suitable output file type. MOV is generally safe.
            // For more specific types, you might inspect avAsset.tracks or rely on the preset.
            // If the exportPreset sets a compatible type, this might not be strictly necessary
            // but it's good for clarity or if a specific format is required.
            if ([exportSession.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie]) {
                exportSession.outputFileType = AVFileTypeQuickTimeMovie;
            } else if (exportSession.supportedFileTypes.count > 0) {
                exportSession.outputFileType = exportSession.supportedFileTypes[0]; // Fallback to the first supported type
            } else {
                [weakSelf failure:command withMessage:@"No supported output file types for export session"];
                return;
            }

            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                    NSData* videoData = [NSData dataWithContentsOfURL:outputURL];
                    if ([weakSelf isNull:videoData]) {
                        [weakSelf failure:command withMessage:@"Failed to read exported video data"];
                    } else {
                        [weakSelf success:command withData:videoData];
                    }
                    // Clean up temporary file
                    [fileManager removeItemAtURL:outputURL error:nil];
                } else if (exportSession.status == AVAssetExportSessionStatusFailed) {
                    NSString* errorMessage = @"Video export failed";
                    if (exportSession.error) {
                        errorMessage = [NSString stringWithFormat:@"Video export failed: %@", exportSession.error.localizedDescription];
                    }
                    [weakSelf failure:command withMessage:errorMessage];
                } else {
                    [weakSelf failure:command withMessage:[NSString stringWithFormat:@"Video export completed with unexpected status: %ld", (long)exportSession.status]];
                }
            }];
        }];
    }];
}

- (void) cancel:(CDVInvokedUrlCommand*)command {
    self.photosCommand = nil;
    [self success:command];
}

#pragma mark - Auxiliary functions

- (void) checkPermissionsOf:(CDVInvokedUrlCommand*)command andRun:(void (^)(void))block {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        switch ([PHPhotoLibrary authorizationStatus]) {
            case PHAuthorizationStatusAuthorized:
                [self.commandDelegate runInBackground:block];
                break;
            default:
                [self failure:command withMessage:E_PERMISSION];
                break;
        }
    }];
}

- (NSString*) getPhotoLibraryAuthorizationStatus
{
    PHAuthorizationStatus authStatus = [PHPhotoLibrary authorizationStatus];
    return [self getPhotoLibraryAuthorizationStatusAsString:authStatus];

}

- (NSString*) getPhotoLibraryAuthorizationStatusAsString: (PHAuthorizationStatus)authStatus
{
    NSString* status;
    if (authStatus == PHAuthorizationStatusDenied || authStatus == PHAuthorizationStatusRestricted){
        status = @"AUTHORIZATION_DENIED";
    } else if(authStatus == PHAuthorizationStatusNotDetermined ){
        status = @"AUTHORIZATION_NOT_DETERMINED";
    } else if(authStatus == PHAuthorizationStatusAuthorized){
        status = @"AUTHORIZATION_GRANTED";
    }
    return status;
}

//GET RIGHT
- (void) getPhotoLibraryAuthorization: (CDVInvokedUrlCommand*)command
{
    CDVPhotos* __weak weakSelf = self;
    [self.commandDelegate runInBackground:^{
        @try {
            NSString* status = [self getPhotoLibraryAuthorizationStatus];
            [weakSelf success:command withMessage:status];
        }
        @catch (NSException *exception) {
            [weakSelf failure:command withMessage:@"Bad Error NSException"];
        }
    }];
}

//REQUEST RIGHT
- (void) requestPhotoLibraryAuthorization: (CDVInvokedUrlCommand*)command
{
    CDVPhotos* __weak weakSelf = self;
    [self.commandDelegate runInBackground:^{
        @try {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus authStatus) {
                NSString* status = [self getPhotoLibraryAuthorizationStatusAsString:authStatus];
                [weakSelf success:command withMessage:status];
            }];
        }
        @catch (NSException *exception) {
            [weakSelf failure:command withMessage:@"Bad Error NSException"];
        }
    }];
}

- (BOOL) isNull:(id)obj {
    return obj == nil || [[NSNull null] isEqual:obj];
}

- (id) argOf:(CDVInvokedUrlCommand*)command
            atIndex:(NSUInteger)idx
          withDefault:(NSObject*)def {
    NSArray* args = command.arguments;
    NSObject* arg = args.count > idx ? args[idx] : nil;
    if ([self isNull:arg]) arg = def;
    return arg;
}

- (id) valueFrom:(NSDictionary*)dictionary byKey:(id)key withDefault:(NSObject*)def {
    id result = dictionary[key];
    if ([self isNull:result]) result = def;
    return result;
}

- (PHAsset*) assetByCommand:(CDVInvokedUrlCommand*)command {
    NSString* assetId = [self argOf:command atIndex:0 withDefault:nil];

    PHFetchOptions* fetchOptions = [[PHFetchOptions alloc] init];
    NSMutableArray<NSSortDescriptor*> * descriptors = [NSMutableArray array];
    NSSortDescriptor* descriptor = [[NSSortDescriptor alloc] initWithKey:S_SORT_TYPE ascending:false];
    [descriptors addObject:descriptor];
    fetchOptions.sortDescriptors = descriptors;
    fetchOptions.includeAllBurstAssets = YES;
    fetchOptions.includeHiddenAssets = YES;
    
    if ([self isNull:assetId]) {
        [self failure:command withMessage:E_PHOTO_ID_UNDEF];
        return nil;
    }
    PHFetchResult<PHAsset*>* fetchResultAssets
    = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:fetchOptions];
    if (fetchResultAssets.count == 0) {
        [self failure:command withMessage:E_PHOTO_ID_WRONG];
        return nil;
    }
    PHAsset* asset = fetchResultAssets.firstObject;
    if (asset.mediaType != PHAssetMediaTypeImage && asset.mediaType != PHAssetMediaTypeVideo) {
        [self failure:command withMessage:@"Asset is neither an image nor a video"];
        return nil;
    }
    return asset;
}

- (NSString*) getFilenameForAsset:(PHAsset*)asset {
// Works fine, but asynchronous ((.
//    [asset
//     requestContentEditingInputWithOptions:nil
//     completionHandler:^(PHContentEditingInput* _Nullable contentEditingInput, NSDictionary* _Nonnull info) {
//         NSString* filename = [[contentEditingInput.fullSizeImageURL.absoluteString componentsSeparatedByString:@"/"] lastObject];
//     }];

// Most optimal and fast, but it's dirty hack
    return [asset valueForKey:@"filename"];

// assetResourcesForAsset doesn't work properly for all images.
// Moreover, it obtains resource for very long time - too long for just a file name.
//    NSArray<PHAssetResource*>* resources = [PHAssetResource assetResourcesForAsset:asset];
//    if ([self isNull:resources] || resources.count == 0) return nil;
//    return resources[0].originalFilename;
}

- (PHFetchResult<PHCollection*>*) fetchCollections:(NSDictionary*)options {
    NSString* mode = [self valueFrom:options
                               byKey:P_C_MODE
                         withDefault:P_C_MODE_ROLL];

    PHAssetCollectionType type;
    PHAssetCollectionSubtype subtype;
    if ([P_C_MODE_ROLL isEqualToString:mode]) {
        type = PHAssetCollectionTypeSmartAlbum;
        subtype = PHAssetCollectionSubtypeSmartAlbumUserLibrary;
    } else if ([P_C_MODE_SMART isEqualToString:mode]) {
        type = PHAssetCollectionTypeSmartAlbum;
        subtype = PHAssetCollectionSubtypeAny;
    } else if ([P_C_MODE_ALBUMS isEqualToString:mode]) {
        return [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    } else if ([P_C_MODE_MOMENTS isEqualToString:mode]) {
        type = PHAssetCollectionTypeMoment;
        subtype = PHAssetCollectionSubtypeAny;
    } else {
        return nil;
    }
    
    return [PHAssetCollection fetchAssetCollectionsWithType:type
                                                    subtype:subtype
                                                    options:nil];
}

- (NSMutableArray<NSDictionary*>*) fetchAllImages {
    CDVPhotos* __weak weakSelf = self;
    
    NSDictionary* options = [weakSelf argOf:self.photosCommand atIndex:1 withDefault:@{}];
    int offset = [[weakSelf valueFrom:options
                                byKey:P_LIST_OFFSET
                          withDefault:@"0"] intValue];
    int limit = [[weakSelf valueFrom:options
                               byKey:P_LIST_LIMIT
                         withDefault:@"0"] intValue];
    
    PHFetchOptions* fetchOptions = [[PHFetchOptions alloc] init];
    NSMutableArray<NSSortDescriptor*> * descriptors = [NSMutableArray array];
    NSSortDescriptor* descriptor = [[NSSortDescriptor alloc] initWithKey:S_SORT_TYPE ascending:false];
    [descriptors addObject:descriptor];
    fetchOptions.sortDescriptors = descriptors;
    fetchOptions.includeAllBurstAssets = YES;
    fetchOptions.includeHiddenAssets = YES;
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeImage];
    
    if (offset == 0) {
        fetchOptions.fetchLimit = limit;
    }
    
    PHFetchResult<PHAsset *> * fetchResultAssets = [PHAsset fetchAssetsWithOptions:fetchOptions];
    
    int __block fetched = 0;
    NSMutableArray<PHAsset*>* __block skippedAssets = [NSMutableArray array];
    NSMutableArray<NSDictionary*>* __block result = [NSMutableArray array];
    [fetchResultAssets enumerateObjectsUsingBlock:
    ^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        if ([weakSelf isNull:weakSelf.photosCommand]) {
            *stop = YES;
            return;
        }
        NSString* filename = [weakSelf getFilenameForAsset:asset];
        if (![weakSelf isNull:filename]) {
            NSTextCheckingResult* match
            = [weakSelf.extRegex
               firstMatchInString:filename
               options:0
               range:NSMakeRange(0, filename.length)];
            if (match != nil) {
                NSString* name = [filename substringWithRange:[match rangeAtIndex:1]];
                NSString* ext = [[filename substringWithRange:[match rangeAtIndex:2]] uppercaseString];
                NSString* type = weakSelf.extType[ext];
                if (![weakSelf isNull:type]) {
                    if (offset <= fetched) {
                        NSMutableDictionary<NSString*, NSObject*>* assetItem
                        = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                           asset.localIdentifier, P_ID,
                           name, P_NAME,
                           type, P_TYPE,
                           [weakSelf.dateFormat stringFromDate:asset.creationDate], P_DATE,
                           @((long) (asset.creationDate.timeIntervalSince1970 * 1000)), P_TS,
                           @(asset.pixelWidth), P_WIDTH,
                           @(asset.pixelHeight), P_HEIGHT,
                           nil];
                        if (![weakSelf isNull:asset.location]) {
                            CLLocationCoordinate2D coord = asset.location.coordinate;
                            [assetItem setValue:@(coord.latitude) forKey:P_LAT];
                            [assetItem setValue:@(coord.longitude) forKey:P_LON];
                        }
                        // Add URI for the video asset
                        NSString* assetIdPathless = [asset.localIdentifier componentsSeparatedByString:@"/"][0];
                        NSString* uriString = [NSString stringWithFormat:@"assets-library://asset/asset.%@?id=%@&ext=%@", ext, assetIdPathless, ext];
                        [assetItem setValue:uriString forKey:P_URI];
                        
                        [result addObject:assetItem];
                        if (limit > 0 && result.count >= limit) {
                            *stop = YES;
                            return ;
                        }
                    }
                    ++fetched;
                } else {
                   [skippedAssets addObject:asset];
               }
            } else {
                [skippedAssets addObject:asset];
            }
        } else {
           [skippedAssets addObject:asset];
        }
    }];
    
    [skippedAssets enumerateObjectsUsingBlock:^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        NSLog(@"skipped asset %lu: id=%@; name=%@, type=%ld-%ld; size=%lux%lu;",
              (long)idx, asset.localIdentifier, [weakSelf getFilenameForAsset:asset],
              (long)asset.mediaType, (long)asset.mediaSubtypes,
              (unsigned long)asset.pixelWidth, (long)asset.pixelHeight);
    }];
    
    return result;
}

- (NSMutableArray<NSDictionary*>*) fetchAllVideos {
    CDVPhotos* __weak weakSelf = self;
    
    NSDictionary* options = [weakSelf argOf:self.photosCommand atIndex:1 withDefault:@{}];
    int offset = [[weakSelf valueFrom:options
                                byKey:P_LIST_OFFSET
                          withDefault:@"0"] intValue];
    int limit = [[weakSelf valueFrom:options
                               byKey:P_LIST_LIMIT
                         withDefault:@"0"] intValue];
    
    PHFetchOptions* fetchOptions = [[PHFetchOptions alloc] init];
    NSMutableArray<NSSortDescriptor*> * descriptors = [NSMutableArray array];
    NSSortDescriptor* descriptor = [[NSSortDescriptor alloc] initWithKey:S_SORT_TYPE ascending:false];
    [descriptors addObject:descriptor];
    fetchOptions.sortDescriptors = descriptors;
    fetchOptions.includeAllBurstAssets = YES;
    fetchOptions.includeHiddenAssets = YES;
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeVideo];
    
    if (offset == 0) {
        fetchOptions.fetchLimit = limit;
    }
    
    PHFetchResult<PHAsset *> * fetchResultAssets = [PHAsset fetchAssetsWithOptions:fetchOptions];
    
    int __block fetched = 0;
    NSMutableArray<PHAsset*>* __block skippedAssets = [NSMutableArray array];
    NSMutableArray<NSDictionary*>* __block result = [NSMutableArray array];
    [fetchResultAssets enumerateObjectsUsingBlock:
    ^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        if ([weakSelf isNull:weakSelf.photosCommand]) {
            *stop = YES;
            return;
        }
        NSString* filename = [weakSelf getFilenameForAsset:asset];
        if (![weakSelf isNull:filename]) {
            NSTextCheckingResult* match
            = [weakSelf.extRegex
               firstMatchInString:filename
               options:0
               range:NSMakeRange(0, filename.length)];
            if (match != nil) {
                NSString* name = [filename substringWithRange:[match rangeAtIndex:1]];
                NSString* ext = [[filename substringWithRange:[match rangeAtIndex:2]] uppercaseString];
                NSString* type = weakSelf.extType[ext];
                if (![weakSelf isNull:type]) {
                    if (offset <= fetched) {
                        NSMutableDictionary<NSString*, NSObject*>* assetItem
                        = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                           asset.localIdentifier, P_ID,
                           name, P_NAME,
                           type, P_TYPE,
                           [weakSelf.dateFormat stringFromDate:asset.creationDate], P_DATE,
                           @((long) (asset.creationDate.timeIntervalSince1970 * 1000)), P_TS,
                           @(asset.pixelWidth), P_WIDTH,
                           @(asset.pixelHeight), P_HEIGHT,
                           nil];
                        if (![weakSelf isNull:asset.location]) {
                            CLLocationCoordinate2D coord = asset.location.coordinate;
                            [assetItem setValue:@(coord.latitude) forKey:P_LAT];
                            [assetItem setValue:@(coord.longitude) forKey:P_LON];
                        }
                        // Add URI for the video asset
                        NSString* assetIdPathless = [asset.localIdentifier componentsSeparatedByString:@"/"][0];
                        NSString* uriString = [NSString stringWithFormat:@"assets-library://asset/asset.%@?id=%@&ext=%@", ext, assetIdPathless, ext];
                        [assetItem setValue:uriString forKey:P_URI];
                        
                        [result addObject:assetItem];
                        if (limit > 0 && result.count >= limit) {
                            *stop = YES;
                            return ;
                        }
                    }
                    ++fetched;
                } else {
                   [skippedAssets addObject:asset];
               }
            } else {
                [skippedAssets addObject:asset];
            }
        } else {
           [skippedAssets addObject:asset];
        }
    }];
    
    [skippedAssets enumerateObjectsUsingBlock:^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        NSLog(@"skipped asset %lu: id=%@; name=%@, type=%ld-%ld; size=%lux%lu;",
              (long)idx, asset.localIdentifier, [weakSelf getFilenameForAsset:asset],
              (long)asset.mediaType, (long)asset.mediaSubtypes,
              (unsigned long)asset.pixelWidth, (long)asset.pixelHeight);
    }];
    
    return result;
}

- (NSMutableArray<NSDictionary*>*) fetchImagesFromCollections:(PHFetchResult<PHAssetCollection*>*)fetchResultAssetCollections {
    CDVPhotos* __weak weakSelf = self;
    
    NSDictionary* options = [weakSelf argOf:self.photosCommand atIndex:1 withDefault:@{}];
    int offset = [[weakSelf valueFrom:options
                                byKey:P_LIST_OFFSET
                          withDefault:@"0"] intValue];
    int limit = [[weakSelf valueFrom:options
                               byKey:P_LIST_LIMIT
                         withDefault:@"0"] intValue];
    int __block fetched = 0;
    NSMutableArray<PHAsset*>* __block skippedAssets = [NSMutableArray array];
    NSMutableArray<NSDictionary*>* __block result = [NSMutableArray array];
    [fetchResultAssetCollections enumerateObjectsUsingBlock:
     ^(PHCollection* _Nonnull collection, NSUInteger idx, BOOL* _Nonnull stop) {
         if ([weakSelf isNull:weakSelf.photosCommand]) {
             *stop = YES;
             return;
         }
        
        if ([collection isKindOfClass:PHAssetCollection.class]) {
            PHAssetCollection* assetCollection = (PHAssetCollection*)collection;
         
            PHFetchOptions* fetchOptions = [[PHFetchOptions alloc] init];
             fetchOptions.sortDescriptors = @[[NSSortDescriptor
                                               sortDescriptorWithKey:@"creationDate"
                                               ascending:NO]];
            if (offset == 0) {
                fetchOptions.fetchLimit = limit;
            }
             fetchOptions.predicate
             = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeImage];

             PHFetchResult<PHAsset*>* fetchResultAssets =
             [PHAsset fetchAssetsInAssetCollection:assetCollection options:fetchOptions];

            
             [fetchResultAssets enumerateObjectsUsingBlock:
              ^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
                  if ([weakSelf isNull:weakSelf.photosCommand]) {
                      *stop = YES;
                      return;
                  }
                  NSString* filename = [weakSelf getFilenameForAsset:asset];
                  if (![weakSelf isNull:filename]) {
                      NSTextCheckingResult* match
                      = [weakSelf.extRegex
                         firstMatchInString:filename
                         options:0
                         range:NSMakeRange(0, filename.length)];
                      if (match != nil) {
                          NSString* name = [filename substringWithRange:[match rangeAtIndex:1]];
                          NSString* ext = [[filename substringWithRange:[match rangeAtIndex:2]] uppercaseString];
                          NSString* type = weakSelf.extType[ext];
                          if (![weakSelf isNull:type]) {
                              if (offset <= fetched) {
                                  NSMutableDictionary<NSString*, NSObject*>* assetItem
                                  = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     asset.localIdentifier, P_ID,
                                     name, P_NAME,
                                     type, P_TYPE,
                                     [weakSelf.dateFormat stringFromDate:asset.creationDate], P_DATE,
                                     @((long) (asset.creationDate.timeIntervalSince1970 * 1000)), P_TS,
                                     @(asset.pixelWidth), P_WIDTH,
                                     @(asset.pixelHeight), P_HEIGHT,
                                     nil];
                                  if (![weakSelf isNull:asset.location]) {
                                      CLLocationCoordinate2D coord = asset.location.coordinate;
                                      [assetItem setValue:@(coord.latitude) forKey:P_LAT];
                                      [assetItem setValue:@(coord.longitude) forKey:P_LON];
                                  }
                                  // Add URI for the video asset
                                  NSString* assetIdPathless = [asset.localIdentifier componentsSeparatedByString:@"/"][0];
                                  NSString* uriString = [NSString stringWithFormat:@"assets-library://asset/asset.%@?id=%@&ext=%@", ext, assetIdPathless, ext];
                                  [assetItem setValue:uriString forKey:P_URI];

                                  [result addObject:assetItem];
                                  if (limit > 0 && result.count >= limit) {
                                      *stop = YES;
                                      return ;
                                  }
                              }
                              ++fetched;
                          } else [skippedAssets addObject:asset];
                      } else [skippedAssets addObject:asset];
                  } else [skippedAssets addObject:asset];
              }];
        } else if ([collection isKindOfClass:PHCollectionList.class]) {
            //nothing todo
        }
     }];
    
    [skippedAssets enumerateObjectsUsingBlock:^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        NSLog(@"skipped asset %lu: id=%@; name=%@, type=%ld-%ld; size=%lux%lu;",
              (long)idx, asset.localIdentifier, [weakSelf getFilenameForAsset:asset],
              (long)asset.mediaType, (long)asset.mediaSubtypes,
              (unsigned long)asset.pixelWidth, (long)asset.pixelHeight);
    }];
    
    return result;
}

- (NSMutableArray<NSDictionary*>*) fetchVideosFromCollections:(PHFetchResult<PHAssetCollection*>*)fetchResultAssetCollections {
    CDVPhotos* __weak weakSelf = self;
    
    NSDictionary* options = [weakSelf argOf:self.photosCommand atIndex:1 withDefault:@{}];
    int offset = [[weakSelf valueFrom:options
                                byKey:P_LIST_OFFSET
                          withDefault:@"0"] intValue];
    int limit = [[weakSelf valueFrom:options
                               byKey:P_LIST_LIMIT
                         withDefault:@"0"] intValue];
    int __block fetched = 0;
    NSMutableArray<PHAsset*>* __block skippedAssets = [NSMutableArray array];
    NSMutableArray<NSDictionary*>* __block result = [NSMutableArray array];
    [fetchResultAssetCollections enumerateObjectsUsingBlock:
     ^(PHCollection* _Nonnull collection, NSUInteger idx, BOOL* _Nonnull stop) {
         if ([weakSelf isNull:weakSelf.photosCommand]) {
             *stop = YES;
             return;
         }
        
        if ([collection isKindOfClass:PHAssetCollection.class]) {
            PHAssetCollection* assetCollection = (PHAssetCollection*)collection;
         
            PHFetchOptions* fetchOptions = [[PHFetchOptions alloc] init];
             fetchOptions.sortDescriptors = @[[NSSortDescriptor
                                               sortDescriptorWithKey:@"creationDate"
                                               ascending:NO]];
            if (offset == 0) {
                fetchOptions.fetchLimit = limit;
            }
             fetchOptions.predicate
             = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeVideo];

             PHFetchResult<PHAsset*>* fetchResultAssets =
             [PHAsset fetchAssetsInAssetCollection:assetCollection options:fetchOptions];

            
             [fetchResultAssets enumerateObjectsUsingBlock:
              ^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
                  if ([weakSelf isNull:weakSelf.photosCommand]) {
                      *stop = YES;
                      return;
                  }
                  NSString* filename = [weakSelf getFilenameForAsset:asset];
                  if (![weakSelf isNull:filename]) {
                      NSTextCheckingResult* match
                      = [weakSelf.extRegex
                         firstMatchInString:filename
                         options:0
                         range:NSMakeRange(0, filename.length)];
                      if (match != nil) {
                          NSString* name = [filename substringWithRange:[match rangeAtIndex:1]];
                          NSString* ext = [[filename substringWithRange:[match rangeAtIndex:2]] uppercaseString];
                          NSString* type = weakSelf.extType[ext];
                          if (![weakSelf isNull:type]) {
                              if (offset <= fetched) {
                                  NSMutableDictionary<NSString*, NSObject*>* assetItem
                                  = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     asset.localIdentifier, P_ID,
                                     name, P_NAME,
                                     type, P_TYPE,
                                     [weakSelf.dateFormat stringFromDate:asset.creationDate], P_DATE,
                                     @((long) (asset.creationDate.timeIntervalSince1970 * 1000)), P_TS,
                                     @(asset.pixelWidth), P_WIDTH,
                                     @(asset.pixelHeight), P_HEIGHT,
                                     nil];
                                  if (![weakSelf isNull:asset.location]) {
                                      CLLocationCoordinate2D coord = asset.location.coordinate;
                                      [assetItem setValue:@(coord.latitude) forKey:P_LAT];
                                      [assetItem setValue:@(coord.longitude) forKey:P_LON];
                                  }
                                  // Add URI for the video asset
                                  NSString* assetIdPathless = [asset.localIdentifier componentsSeparatedByString:@"/"][0];
                                  NSString* uriString = [NSString stringWithFormat:@"assets-library://asset/asset.%@?id=%@&ext=%@", ext, assetIdPathless, ext];
                                  [assetItem setValue:uriString forKey:P_URI];

                                  [result addObject:assetItem];
                                  if (limit > 0 && result.count >= limit) {
                                      *stop = YES;
                                      return ;
                                  }
                              }
                              ++fetched;
                          } else [skippedAssets addObject:asset];
                      } else [skippedAssets addObject:asset];
                  } else [skippedAssets addObject:asset];
              }];
        } else if ([collection isKindOfClass:PHCollectionList.class]) {
            //nothing todo
        }
     }];
    
    [skippedAssets enumerateObjectsUsingBlock:^(PHAsset* _Nonnull asset, NSUInteger idx, BOOL* _Nonnull stop) {
        NSLog(@"skipped asset %lu: id=%@; name=%@, type=%ld-%ld; size=%lux%lu;",
              (long)idx, asset.localIdentifier, [weakSelf getFilenameForAsset:asset],
              (long)asset.mediaType, (long)asset.mediaSubtypes,
              (unsigned long)asset.pixelWidth, (long)asset.pixelHeight);
    }];
    
    return result;
}

#pragma mark - Callback methods

- (void) success:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate
     sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
     callbackId:command.callbackId];
}

- (void) success:(CDVInvokedUrlCommand*)command withMessage:(NSString*)message {
    [self.commandDelegate
     sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                        messageAsString:message]
     callbackId:command.callbackId];
}

- (void) success:(CDVInvokedUrlCommand*)command withArray:(NSArray*)array {
    [self.commandDelegate
     sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsArray:array]
     callbackId:command.callbackId];
}

- (void) success:(CDVInvokedUrlCommand*)command withData:(NSData*)data {
    [self.commandDelegate
     sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                   messageAsArrayBuffer:data]
     callbackId:command.callbackId];
}

- (void) partial:(CDVInvokedUrlCommand*)command withArray:(NSArray*)array {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                 messageAsArray:array];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void) failure:(CDVInvokedUrlCommand*)command withMessage:(NSString*)message {
    [self.commandDelegate
     sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                        messageAsString:message]
     callbackId:command.callbackId];
}

@end
