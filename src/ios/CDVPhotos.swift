import Foundation
import Photos
// Assuming CDVPlugin is the base class, adjust if necessary
// import Cordova // Or the specific Cordova module

// MARK: - Constants
private enum Constants {
    static let pId = "id"
    static let pName = "name"
    static let pWidth = "width"
    static let pHeight = "height"
    static let pLat = "latitude"
    static let pLon = "longitude"
    static let pDate = "date"
    static let pTs = "timestamp"
    static let pType = "contentType"
    static let pUri = "uri"
    static let pCount = "count"

    static let pSize = "dimension"
    static let pQuality = "quality"
    static let pAsDataUrl = "asDataUrl"

    static let pCMode = "collectionMode"
    static let pCModeRoll = "ROLL"
    static let pCModeSmart = "SMART"
    static let pCModeAlbums = "ALBUMS"
    static let pCModeMoments = "MOMENTS"

    static let pListOffset = "offset"
    static let pListLimit = "limit"
    static let pListInterval = "interval"

    static let tDataUrl = "data:image/jpeg;base64,%@"
    static let tDateFormat = "YYYY-MM-dd'T'HH:mm:ssZZZZZ"
    static let tExtPattern = "^(.+)\\.([a-z]{3,4})$"

    static let defSize: Int = 120
    static let defQuality: Int = 80
    static let defName = "No Name"

    static let ePermission = "Access to Photo Library permission required"
    static let eCollectionMode = "Unsupported collection mode"
    static let ePhotoNoData = "Specified photo has no data"
    static let ePhotoThumb = "Cannot get a thumbnail of photo"
    static let ePhotoIdUndef = "Photo ID is undefined"
    static let ePhotoIdWrong = "Photo with specified ID wasn't found"
    static let ePhotoNotImage = "Data with specified ID isn't an image"
    static let ePhotoBusy = "Fetching of photo assets is in progress"

    static let sSortType = "creationDate"

    enum AuthorizationStatusString: String {
        case denied = "AUTHORIZATION_DENIED"
        case notDetermined = "AUTHORIZATION_NOT_DETERMINED"
        case granted = "AUTHORIZATION_GRANTED"
    }
}

@objc(CDVPhotos)
class CDVPhotos: CDVPlugin {

    private lazy var dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.tDateFormat
        return formatter
    }()

    private lazy var extType: [String: String] = {
        return [
            "JPG": "image/jpeg",
            "JPEG": "image/jpeg",
            "PNG": "image/png",
            "GIF": "image/gif",
            "TIF": "image/tiff",
            "TIFF": "image/tiff",
            "HEIC": "image/jpeg", // HEIC can often be converted to JPEG for broader compatibility
            "MP4": "video/mp4",
            "MOV": "video/quicktime",
            "AVI": "video/x-msvideo",
            "MPEG": "video/mpeg",
            "MPG": "video/mpeg",
            "MPEG-4": "video/mp4",
            "M4V": "video/mp4",
            "M4A": "audio/mp4",
            "AAC": "audio/mp4",
            "MP3": "audio/mp3",
            "WAV": "audio/wav",
            "WMA": "audio/x-ms-wma"
        ]
    }()

    private lazy var extRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: Constants.tExtPattern,
                                           options: [.caseInsensitive, .dotMatchesLineSeparators, .anchorsMatchLines])
        } catch {
            print("Error creating regex: \(error)")
            return nil
        }
    }()

    private var photosCommand: CDVInvokedUrlCommand?

    override func pluginInitialize() {
        super.pluginInitialize()
        // Properties are initialized lazily, so no explicit setup needed here
        // for dateFormat, extType, extRegex unless specific non-lazy init is required.
    }

    // MARK: - Helper methods for command arguments and results (to be implemented)
    private func arg<T>(of command: CDVInvokedUrlCommand, at index: Int, default defaultValue: T) -> T {
        guard let arg = command.argument(at: UInt(index)) as? T, arg as? NSNull != NSNull() else {
            return defaultValue
        }
        return arg
    }
    
    private func valueFrom<T>(dictionary: [AnyHashable: Any], byKey key: String, default defaultValue: T) -> T {
        guard let value = dictionary[key] as? T, value as? NSNull != NSNull() else {
            return defaultValue
        }
        return value
    }

    private func isNull(_ value: Any?) -> Bool {
        return value == nil || value is NSNull
    }
    
    // MARK: - Callback methods
    private func success(command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    private func success(command: CDVInvokedUrlCommand, message: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    private func success(command: CDVInvokedUrlCommand, array: [Any]) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: array)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    private func success(command: CDVInvokedUrlCommand, data: Data) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAsArrayBuffer: data)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    private func partial(command: CDVInvokedUrlCommand, array: [Any]) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: array)
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    private func failure(command: CDVInvokedUrlCommand, message: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // MARK: - Permissions
    private func checkPermissions(of command: CDVInvokedUrlCommand, andRun block: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            self.commandDelegate.run { // Using commandDelegate.run to ensure it runs on a background thread if needed by Cordova
                block()
            }
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                if newStatus == .authorized {
                    self?.commandDelegate.run {
                        block()
                    }
                } else {
                    self?.failure(command: command, message: Constants.ePermission)
                }
            }
        default:
            self.failure(command: command, message: Constants.ePermission)
        }
    }

    private func getPhotoLibraryAuthorizationStatusString() -> String {
        let authStatus = PHPhotoLibrary.authorizationStatus()
        return getPhotoLibraryAuthorizationStatusString(for: authStatus)
    }

    private func getPhotoLibraryAuthorizationStatusString(for authStatus: PHAuthorizationStatus) -> String {
        switch authStatus {
        case .denied, .restricted:
            return Constants.AuthorizationStatusString.denied.rawValue
        case .notDetermined:
            return Constants.AuthorizationStatusString.notDetermined.rawValue
        case .authorized:
            return Constants.AuthorizationStatusString.granted.rawValue
        case .limited: // iOS 14+
             return Constants.AuthorizationStatusString.granted.rawValue // Or a new "LIMITED" status if your JS expects it
        @unknown default:
            return Constants.AuthorizationStatusString.notDetermined.rawValue // Or handle appropriately
        }
    }

    @objc(getPhotoLibraryAuthorization:)
    func getPhotoLibraryAuthorization(command: CDVInvokedUrlCommand) {
        self.commandDelegate.run { [weak self] in
            guard let self = self else { return }
            do {
                let status = self.getPhotoLibraryAuthorizationStatusString()
                self.success(command: command, message: status)
            } catch {
                self.failure(command: command, message: "Bad Error NSException") // Consider more specific error
            }
        }
    }

    @objc(requestPhotoLibraryAuthorization:)
    func requestPhotoLibraryAuthorization(command: CDVInvokedUrlCommand) {
        self.commandDelegate.run { [weak self] in
            guard let self = self else { return }
            do {
                PHPhotoLibrary.requestAuthorization { [weak self] authStatus in
                    guard let self = self else { return }
                    let statusString = self.getPhotoLibraryAuthorizationStatusString(for: authStatus)
                    self.success(command: command, message: statusString)
                }
            } catch {
                 self.failure(command: command, message: "Bad Error NSException") // Consider more specific error
            }
        }
    }

    // MARK: - Command Implementations
    @objc(collections:)
    func collections(command: CDVInvokedUrlCommand) {
        checkPermissions(of: command) { [weak self] in
            guard let self = self else { return }
            
            let options: [String: Any] = self.arg(of: command, at: 0, default: [:] as [String: Any])
            
            guard let fetchResultCollections = self.fetchCollections(options: options) else {
                self.failure(command: command, message: Constants.eCollectionMode)
                return
            }
            
            var resultCollections: [PHCollection] = []
            fetchResultCollections.enumerateObjects {(collection, _, _) in
                // Original code adds both PHCollectionList and PHAssetCollection
                // and then filters. We can potentially filter earlier or keep the logic.
                // For now, let's keep it similar.
                resultCollections.append(collection)
            }
            
            let filteredAssetCollections = resultCollections.compactMap { $0 as? PHAssetCollection }.filter { $0.canContainAssets }

            let result: [[String: Any]] = filteredAssetCollections.map { assetCollection in
                let count = assetCollection.estimatedAssetCount
                let title = assetCollection.localizedTitle ?? Constants.defName
                
                var collectionItem: [String: Any] = [
                    Constants.pId: assetCollection.localIdentifier,
                    Constants.pName: title,
                    Constants.pCount: "\(count)"
                ]
                return collectionItem
            }
            self.success(command: command, array: result)
        }
    }

    // MARK: - Auxiliary functions (to be implemented or moved)
    private func fetchCollections(options: [String: Any]) -> PHFetchResult<PHCollection>? {
        let mode = valueFrom(dictionary: options, byKey: Constants.pCMode, default: Constants.pCModeRoll)

        if mode == Constants.pCModeRoll {
            return PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil) as? PHFetchResult<PHCollection>
        } else if mode == Constants.pCModeSmart {
            return PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil) as? PHFetchResult<PHCollection>
        } else if mode == Constants.pCModeAlbums {
            return PHCollectionList.fetchTopLevelUserCollections(with: nil) as? PHFetchResult<PHCollection>
        } else if mode == Constants.pCModeMoments {
            return PHAssetCollection.fetchAssetCollections(with: .moment, subtype: .any, options: nil) as? PHFetchResult<PHCollection>
        } else {
            return nil
        }
    }

    private func assetByCommand(command: CDVInvokedUrlCommand) -> PHAsset? {
        guard let assetId: String = arg(of: command, at: 0, default: nil) else {
            failure(command: command, message: Constants.ePhotoIdUndef)
            return nil
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: Constants.sSortType, ascending: false)]
        fetchOptions.includeAllBurstAssets = true
        fetchOptions.includeHiddenAssets = true
        
        let fetchResultAssets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: fetchOptions)
        
        guard fetchResultAssets.count > 0 else {
            failure(command: command, message: Constants.ePhotoIdWrong)
            return nil
        }
        
        guard let asset = fetchResultAssets.firstObject else {
            // Should not happen if count > 0, but good for safety
            failure(command: command, message: Constants.ePhotoIdWrong)
            return nil
        }
        
        if asset.mediaType != .image && asset.mediaType != .video {
            failure(command: command, message: "Asset is neither an image nor a video")
            return nil
        }
        return asset
    }

    private func getFilenameForAsset(asset: PHAsset) -> String? {
        // Original Objective-C code uses [asset valueForKey:@"filename"];
        // This is the Swift equivalent using KVC.
        return asset.value(forKey: "filename") as? String
    }

    @objc(photos:)
    func photos(command: CDVInvokedUrlCommand) {
        if self.photosCommand != nil {
            self.failure(command: command, message: Constants.ePhotoBusy)
            return
        }
        self.photosCommand = command
        
        checkPermissions(of: command) { [weak self] in
            guard let self = self else {
                // If self is nil, the command might be orphaned.
                // Consider if a failure message should be sent even if photosCommand was set.
                // For now, if self is nil, photosCommand won't be cleared, which might be an issue.
                // However, the original Obj-C also has this potential issue if weakSelf is nil before clearing.
                return
            }
            
            let collectionIds: [String]? = self.arg(of: command, at: 0, default: nil)
            // NSLog(@"photos: collectionIds=%@", collectionIds);
            print("photos: collectionIds=\(collectionIds ?? [])")
            
            var result: [[String: Any]]? = nil
            
            if collectionIds == nil || collectionIds!.isEmpty {
                result = self.fetchAllMedia(ofType: .image, command: command)
            } else {
                let fetchResultAssetCollections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: collectionIds!, options: nil)
                
                if fetchResultAssetCollections.count == 0 && !collectionIds!.isEmpty {
                     // This case might indicate wrong collection IDs were provided.
                     // Original code doesn't explicitly check fetchResultAssetCollections for nil or empty before proceeding
                     // but relies on fetchImagesFromCollections to handle it (which might return empty).
                     // For clarity, we could add a specific failure here if needed, or let it return empty as before.
                    print("Warning: No collections found for given IDs: \(collectionIds!)")
                }
                result = self.fetchMediaFromCollections(ofType: .image, fetchResultAssetCollections: fetchResultAssetCollections, command: command)
            }
            
            self.photosCommand = nil
            if let res = result {
                self.success(command: command, array: res)
            } else {
                // This case should ideally be handled by sub-methods sending a failure
                self.failure(command: command, message: "Failed to fetch photos.")
            }
        }
    }

    // Generic media fetching function to be used by photos and videos
    private func fetchAllMedia(ofType mediaType: PHAssetMediaType, command: CDVInvokedUrlCommand) -> [[String: Any]]? {
        guard let currentCommand = self.photosCommand else { return nil } // Ensure command context is valid
        
        let options: [String: Any] = self.arg(of: currentCommand, at: 1, default: [:] as [String: Any])
        let offset = valueFrom(dictionary: options, byKey: Constants.pListOffset, default: "0").toInt() ?? 0
        let limit = valueFrom(dictionary: options, byKey: Constants.pListLimit, default: "0").toInt() ?? 0

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: Constants.sSortType, ascending: false)]
        fetchOptions.includeAllBurstAssets = true
        fetchOptions.includeHiddenAssets = true
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", mediaType.rawValue)
        
        if offset == 0 && limit > 0 { // Original logic: fetchLimit is only applied if offset is 0.
            fetchOptions.fetchLimit = limit
        }
        
        let fetchResultAssets = PHAsset.fetchAssets(with: fetchOptions)
        var fetchedCount = 0
        var skippedAssets: [PHAsset] = []
        var result: [[String: Any]] = []

        fetchResultAssets.enumerateObjects { [weak self] (asset, _, stop) in
            guard let self = self else { return }
            if self.photosCommand == nil { // Check if the command was cancelled
                stop.pointee = true
                return
            }

            guard let filename = self.getFilenameForAsset(asset: asset) else {
                skippedAssets.append(asset)
                return
            }
            
            guard let regex = self.extRegex, 
                  let match = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) else {
                skippedAssets.append(asset)
                return
            }

            let nsFilename = filename as NSString
            let name = nsFilename.substring(with: match.range(at: 1))
            let ext = nsFilename.substring(with: match.range(at: 2)).uppercased()
            
            guard let type = self.extType[ext] else {
                skippedAssets.append(asset)
                return
            }
            
            // Apply offset and limit logic
            // The original Objective-C code applies offset *before* checking the limit condition.
            // And increments `fetched` for every processed item, regardless of whether it matches the type.
            // The Swift version needs to replicate this carefully.
            
            if fetchedCount >= offset { // Only add to result if past the offset
                var assetItem: [String: Any] = [
                    Constants.pId: asset.localIdentifier,
                    Constants.pName: name,
                    Constants.pType: type,
                    Constants.pDate: self.dateFormat.string(from: asset.creationDate ?? Date()),
                    Constants.pTs: Int64((asset.creationDate ?? Date()).timeIntervalSince1970 * 1000),
                    Constants.pWidth: asset.pixelWidth,
                    Constants.pHeight: asset.pixelHeight
                ]
                
                if let location = asset.location {
                    assetItem[Constants.pLat] = location.coordinate.latitude
                    assetItem[Constants.pLon] = location.coordinate.longitude
                }
                
                let assetIdPathless = asset.localIdentifier.components(separatedBy: "/").first ?? ""
                let uriString = "assets-library://asset/asset.\(ext.lowercased())?id=\(assetIdPathless)&ext=\(ext.lowercased())"
                assetItem[Constants.pUri] = uriString
                
                result.append(assetItem)
                
                if limit > 0 && result.count >= limit {
                    stop.pointee = true
                    return
                }
            }
            fetchedCount += 1
        }
        
        skippedAssets.forEach { asset in
            print("skipped asset: id=\(asset.localIdentifier); name=\(self.getFilenameForAsset(asset: asset) ?? "N/A"), type=\(asset.mediaType.rawValue)-\(asset.mediaSubtypes.rawValue); size=\(asset.pixelWidth)x\(asset.pixelHeight);")
        }
        
        return result
    }

    private func fetchMediaFromCollections(ofType mediaType: PHAssetMediaType, fetchResultAssetCollections: PHFetchResult<PHAssetCollection>, command: CDVInvokedUrlCommand) -> [[String: Any]]? {
        guard let currentCommand = self.photosCommand else { return nil } // Ensure command context is valid

        let options: [String: Any] = self.arg(of: currentCommand, at: 1, default: [:] as [String: Any])
        let offset = valueFrom(dictionary: options, byKey: Constants.pListOffset, default: "0").toInt() ?? 0
        let limit = valueFrom(dictionary: options, byKey: Constants.pListLimit, default: "0").toInt() ?? 0
        
        var fetchedCount = 0
        var skippedAssets: [PHAsset] = []
        var result: [[String: Any]] = []

        fetchResultAssetCollections.enumerateObjects { [weak self] (assetCollection, _, stopCollections) in 
            guard let self = self else { return }
            if self.photosCommand == nil { // Check if the command was cancelled
                stopCollections.pointee = true
                return
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: Constants.sSortType, ascending: false)]
            // Original ObjC applies fetchLimit here only if offset is 0. This might be different from fetchAllMedia.
            // For consistency and based on typical pagination, limit should apply to the number of items *returned*,
            // and offset to items *skipped*.
            // Let's adjust for clarity: fetch all that match, then apply offset/limit post-fetch or during enumeration.
            // The original code's fetchLimit in fetchAssetsInAssetCollection when offset is 0 is a bit tricky.
            // It means if offset=0, limit=10, it fetches at most 10. If offset=5, limit=10, it fetches all then skips.
            // Let's try to replicate: if offset == 0 and limit > 0, apply fetchLimit.
            if offset == 0 && limit > 0 {
                 fetchOptions.fetchLimit = limit // This limits items *per collection* if applied here.
            }
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", mediaType.rawValue)

            let fetchResultAssets = PHAsset.fetchAssets(in: assetCollection, options: fetchOptions)
            
            fetchResultAssets.enumerateObjects { (asset, _, stopAssets) in
                if self.photosCommand == nil { // Check if the command was cancelled
                    stopAssets.pointee = true
                    stopCollections.pointee = true // also stop outer loop
                    return
                }

                guard let filename = self.getFilenameForAsset(asset: asset) else {
                    skippedAssets.append(asset)
                    return
                }
                
                guard let regex = self.extRegex, 
                      let match = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) else {
                    skippedAssets.append(asset)
                    return
                }

                let nsFilename = filename as NSString
                let name = nsFilename.substring(with: match.range(at: 1))
                let ext = nsFilename.substring(with: match.range(at: 2)).uppercased()
                
                guard let type = self.extType[ext] else {
                    skippedAssets.append(asset)
                    return
                }
                
                if fetchedCount >= offset {
                    var assetItem: [String: Any] = [
                        Constants.pId: asset.localIdentifier,
                        Constants.pName: name,
                        Constants.pType: type,
                        Constants.pDate: self.dateFormat.string(from: asset.creationDate ?? Date()),
                        Constants.pTs: Int64((asset.creationDate ?? Date()).timeIntervalSince1970 * 1000),
                        Constants.pWidth: asset.pixelWidth,
                        Constants.pHeight: asset.pixelHeight
                    ]
                    
                    if let location = asset.location {
                        assetItem[Constants.pLat] = location.coordinate.latitude
                        assetItem[Constants.pLon] = location.coordinate.longitude
                    }
                    
                    let assetIdPathless = asset.localIdentifier.components(separatedBy: "/").first ?? ""
                    let uriString = "assets-library://asset/asset.\(ext.lowercased())?id=\(assetIdPathless)&ext=\(ext.lowercased())"
                    assetItem[Constants.pUri] = uriString
                    
                    result.append(assetItem)
                    
                    if limit > 0 && result.count >= limit {
                        stopAssets.pointee = true
                        stopCollections.pointee = true // Stop outer loop as well
                        return
                    }
                }
                fetchedCount += 1
            }
            // If limit is applied globally (not per collection), this check is needed outside asset loop.
            if limit > 0 && result.count >= limit {
                 stopCollections.pointee = true
                 return
            }
        }
        
        skippedAssets.forEach { asset in
            print("skipped asset: id=\(asset.localIdentifier); name=\(self.getFilenameForAsset(asset: asset) ?? "N/A"), type=\(asset.mediaType.rawValue)-\(asset.mediaSubtypes.rawValue); size=\(asset.pixelWidth)x\(asset.pixelHeight);")
        }
        return result
    }

    @objc(videos:)
    func videos(command: CDVInvokedUrlCommand) {
        if self.photosCommand != nil { // Shared with photos, as per original Obj-C
            self.failure(command: command, message: Constants.ePhotoBusy)
            return
        }
        self.photosCommand = command
        
        checkPermissions(of: command) { [weak self] in
            guard let self = self else {
                // As with photos method, consider implications if self is nil here.
                return
            }
            
            let collectionIds: [String]? = self.arg(of: command, at: 0, default: nil)
            // NSLog(@"videos: collectionIds=%@", collectionIds);
            print("videos: collectionIds=\(collectionIds ?? [])")
            
            var result: [[String: Any]]? = nil
            
            if collectionIds == nil || collectionIds!.isEmpty {
                result = self.fetchAllMedia(ofType: .video, command: command)
            } else {
                let fetchResultAssetCollections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: collectionIds!, options: nil)
                
                if fetchResultAssetCollections.count == 0 && !collectionIds!.isEmpty {
                     print("Warning: No collections found for given IDs: \(collectionIds!)")
                }
                result = self.fetchMediaFromCollections(ofType: .video, fetchResultAssetCollections: fetchResultAssetCollections, command: command)
            }
            
            self.photosCommand = nil // Clear the shared command
            if let res = result {
                self.success(command: command, array: res)
            } else {
                // This case should ideally be handled by sub-methods sending a failure
                self.failure(command: command, message: "Failed to fetch videos.")
            }
        }
    }

    @objc(thumbnail:)
    func thumbnail(command: CDVInvokedUrlCommand) {
        checkPermissions(of: command) { [weak self] in
            guard let self = self else { return }
            
            guard let asset = self.assetByCommand(command: command) else {
                // assetByCommand already sends failure
                return
            }
            
            let options: [String: Any] = self.arg(of: command, at: 1, default: [:] as [String: Any])
            let sizeOpt = self.valueFrom(dictionary: options, byKey: Constants.pSize, default: NSNumber(value: Constants.defSize)) // Keep as NSNumber for integerValue
            let qualityOpt = self.valueFrom(dictionary: options, byKey: Constants.pQuality, default: NSNumber(value: Constants.defQuality))
            
            var size = sizeOpt.intValue
            if size <= 0 { size = Constants.defSize }
            var quality = qualityOpt.intValue
            if quality <= 0 { quality = Constants.defQuality }
            let asDataUrl = self.valueFrom(dictionary: options, byKey: Constants.pAsDataUrl, default: false)

            if asset.mediaType == .image {
                let reqOptions = PHImageRequestOptions()
                reqOptions.resizeMode = .exact // PHImageRequestOptionsResizeModeExact
                reqOptions.isNetworkAccessAllowed = true
                reqOptions.isSynchronous = true // For direct result handling as in ObjC
                reqOptions.deliveryMode = .highQualityFormat // PHImageRequestOptionsDeliveryModeHighQualityFormat

                PHImageManager.default().requestImage(for: asset, 
                                                      targetSize: CGSize(width: size, height: size), 
                                                      contentMode: .default, // PHImageContentModeDefault
                                                      options: reqOptions) { [weak self] (resultImage, info) in
                    guard let self = self else { return }
                    
                    if let error = info?[PHImageErrorKey] as? Error {
                        self.failure(command: command, message: error.localizedDescription)
                        return
                    }
                    guard let image = resultImage else {
                        self.failure(command: command, message: Constants.ePhotoNoData)
                        return
                    }

                    // The original code draws the image into a new context.
                    // This might be to ensure the exact size or deal with orientation implicitly.
                    // For safety, replicating this step.
                    UIGraphicsBeginImageContext(image.size)
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                    let processedImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    guard let finalImage = processedImage, let data = finalImage.jpegData(compressionQuality: CGFloat(quality) / 100.0) else {
                        self.failure(command: command, message: Constants.ePhotoThumb)
                        return
                    }
                    
                    if asDataUrl {
                        let dataUrl = String(format: Constants.tDataUrl, data.base64EncodedString())
                        self.success(command: command, message: dataUrl)
                    } else {
                        self.success(command: command, data: data)
                    }
                }
            } else if asset.mediaType == .video {
                let videoReqOptions = PHVideoRequestOptions()
                videoReqOptions.isNetworkAccessAllowed = true
                videoReqOptions.version = .original // PHVideoRequestOptionsVersionOriginal
                
                PHImageManager.default().requestAVAsset(forVideo: asset, options: videoReqOptions) { [weak self] (avAsset, audioMix, info) in
                    guard let self = self else { return }

                    if let error = info?[PHImageErrorKey] as? Error {
                        self.failure(command: command, message: error.localizedDescription)
                        return
                    }
                    guard let avAsset = avAsset else {
                        self.failure(command: command, message: "Could not load video asset")
                        return
                    }
                    
                    var targetWidth = CGFloat(size)
                    var targetHeight = CGFloat(size)
                    let videoTrack = avAsset.tracks(withMediaType: .video).first
                    
                    if let track = videoTrack {
                        let naturalSize = track.naturalSize.applying(track.preferredTransform)
                        let videoWidth = abs(naturalSize.width) // abs for orientation
                        let videoHeight = abs(naturalSize.height)
                        if videoWidth > 0 && videoHeight > 0 {
                            let aspectRatio = videoWidth / videoHeight
                            if videoWidth > videoHeight { // Landscape
                                targetHeight = CGFloat(size) / aspectRatio
                            } else { // Portrait or Square
                                targetWidth = CGFloat(size) * aspectRatio
                            }
                        }
                    } else {
                        // Fallback if track info is not available, use asset pixel dimensions
                        let videoWidth = CGFloat(asset.pixelWidth)
                        let videoHeight = CGFloat(asset.pixelHeight)
                         if videoWidth > 0 && videoHeight > 0 {
                            let aspectRatio = videoWidth / videoHeight
                            if videoWidth > videoHeight {
                                targetHeight = CGFloat(size) / aspectRatio
                            } else {
                                targetWidth = CGFloat(size) * aspectRatio
                            }
                        }
                    }

                    let generator = AVAssetImageGenerator(asset: avAsset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: targetWidth, height: targetHeight)
                    
                    do {
                        let cgImage = try generator.copyCGImage(at: CMTime(value: 0, timescale: 1), actualTime: nil)
                        let image = UIImage(cgImage: cgImage)
                        
                        // Draw to context to ensure size and no rotation issues from generator
                        UIGraphicsBeginImageContext(CGSize(width: targetWidth, height: targetHeight))
                        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
                        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        
                        guard let finalThumbnail = thumbnail, let data = finalThumbnail.jpegData(compressionQuality: CGFloat(quality) / 100.0) else {
                            self.failure(command: command, message: Constants.ePhotoThumb)
                            return
                        }
                        
                        if asDataUrl {
                            let dataUrl = String(format: Constants.tDataUrl, data.base64EncodedString())
                            self.success(command: command, message: dataUrl)
                        } else {
                            self.success(command: command, data: data)
                        }
                    } catch let error {
                        self.failure(command: command, message: error.localizedDescription)
                        return
                    }
                }
            } else {
                 self.failure(command: command, message: "Asset is not an image or video type for thumbnail generation.")
            }
        }
    }

    @objc(image:)
    func image(command: CDVInvokedUrlCommand) {
        checkPermissions(of: command) { [weak self] in
            guard let self = self else { return }
            
            guard let asset = self.assetByCommand(command: command) else {
                // assetByCommand already sends failure
                return
            }

            // In Swift, requestImageDataAndOrientation is preferred over requestImageData for modern handling
            let reqOptions = PHImageRequestOptions()
            reqOptions.isNetworkAccessAllowed = true
            reqOptions.progressHandler = { (progress, error, stop, info) in
                print("progress: \(String(format: "%.2f", progress)), info: \(info ?? [:])")
                if let error = error {
                    print("error: \(error)")
                    stop.pointee = true
                }
            }
            // reqOptions.isSynchronous = false // Prefer async for better UX, though original might have implied sync by its structure
            // reqOptions.version = .current // Get the most recent version including edits
            // reqOptions.deliveryMode = .highQualityFormat

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: reqOptions) { [weak self] (imageData, dataUTI, orientation, info) in
                guard let self = self else { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    self.failure(command: command, message: error.localizedDescription)
                    return
                }
                guard let data = imageData else {
                    self.failure(command: command, message: Constants.ePhotoNoData)
                    return
                }
                
                guard let image = UIImage(data: data) else {
                    self.failure(command: command, message: "Could not create UIImage from data.")
                    return
                }
                
                // The UIImage(data: data) should handle orientation correctly by default.
                // The rotateUIImage method from ObjC might be redundant if UIImage applies EXIF correctly.
                // However, for parity, let's include a similar rotation if necessary.
                // CGImagePropertyOrientation is 1-indexed, UIImage.Orientation is 0-indexed from iOS 13
                // For simplicity, we let UIImage handle orientation from data.
                // If specific rotation matching the old method is needed, it has to be carefully mapped.
                // The original `rotateUIImage` only transforms for Left, Right, Down. Up and mirrored are returned as is.
                // Modern UIImage init from data usually handles this.
                // Let's assume UIImage(data:data) correctly orientates. If not, the rotateUIImage function would be needed.

                // The original code always converts to JPEG. UIImage.jpegData is the way.
                guard let mediaData = image.jpegData(compressionQuality: 1.0) else {
                     self.failure(command: command, message: "Could not get JPEG representation of image.")
                     return
                }
                self.success(command: command, data: mediaData)
            }
        }
    }

    // UIImage(data: data) generally handles orientation correctly.
    // If specific manual rotation like the original Objective-C code is required,
    // this function would need to be implemented carefully, mapping UIImage.Orientation
    // to the specific transforms. For now, relying on modern UIImage behavior.
    /*
    private func rotateUIImage(sourceImage: UIImage, orientation: CGImagePropertyOrientation) -> UIImage {
        // This function would need careful implementation if UIImage(data:) isn't sufficient.
        // The original logic was specific about which orientations to transform.
        // Modern iOS handles many orientations automatically when loading image data.
        return sourceImage // Placeholder
    }
    */

    @objc(video:)
    func video(command: CDVInvokedUrlCommand) {
        checkPermissions(of: command) { [weak self] in
            guard let self = self else { return }
            
            guard let asset = self.assetByCommand(command: command) else {
                // assetByCommand already sends failure
                return
            }

            guard asset.mediaType == .video else {
                self.failure(command: command, message: "Asset is not a video")
                return
            }

            // Setting isNetworkAccessAllowed to true allows Photos to download the video from iCloud if it is not on the local device.
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .original // Get original video

            options.progressHandler = { [weak self] progress, error, stop, info in
                guard let self = self else { return }

                if let error = error {
                    print("Error downloading video from iCloud: \(error.localizedDescription)")
                    stop.pointee = true
                    // The export session will also fail, which will send a failure message.
                    return
                }

                // Send progress update to JavaScript
                let progressUpdate: [String: Any] = ["type": "download_progress", "progress": progress]
                let pluginResult = CDVPluginResult(status: .ok, messageAs: progressUpdate)
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            }

            PHImageManager.default().requestExportSession(forVideo: asset, 
                                                          options: options, 
                                                          exportPreset: AVAssetExportPresetHighestQuality) { [weak self] (exportSession, info) in
                guard let self = self else { return }

                if let error = info?[PHImageErrorKey] as? Error { // Check for specific PHImageErrorKey
                    self.failure(command: command, message: error.localizedDescription)
                    return
                }

                guard let session = exportSession else {
                    self.failure(command: command, message: "Could not create export session for video asset")
                    return
                }

                let outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_")).mov")
                
                // Remove existing file if any
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: outputFilePath.path) {
                    do {
                        try fileManager.removeItem(at: outputFilePath)
                    } catch let error {
                        self.failure(command: command, message: "Could not remove existing temp file: \(error.localizedDescription)")
                        return
                    }
                }
                
                session.outputURL = outputFilePath
                
                // Determine a suitable output file type.
                if session.supportedFileTypes.contains(.mov) {
                    session.outputFileType = .mov
                } else if let firstSupportedType = session.supportedFileTypes.first {
                    session.outputFileType = firstSupportedType
                } else {
                    self.failure(command: command, message: "No supported output file types for export session")
                    return
                }

                session.exportAsynchronously { [weak self] in
                    guard let self = self else { return }
                    switch session.status {
                    case .completed:
                        do {
							let result = ["type":"download_complete","uri": outputFilePath.absoluteString]
                            self.success(command: command, data: result)
                        } catch {
                            self.failure(command: command, message: "Failed to read exported video data: \(error.localizedDescription)")
                        }
                        // Clean up temporary file
                        try? fileManager.removeItem(at: outputFilePath)
                    case .failed:
                        let errorMessage = session.error?.localizedDescription ?? "Video export failed with unknown error"
                        self.failure(command: command, message: "Video export failed: \(errorMessage)")
                    case .cancelled:
                        self.failure(command: command, message: "Video export cancelled")
                    default:
                        self.failure(command: command, message: "Video export completed with unexpected status: \(session.status.rawValue)")
                    }
                }
            }
        }
    }

    @objc(cancel:)
    func cancel(command: CDVInvokedUrlCommand) {
        // The photosCommand is shared by photos and videos fetching operations.
        // Setting it to nil should signal those operations to stop if they are checking it.
        self.photosCommand = nil 
        self.success(command: command) // Send OK for cancellation itself
    }
}

extension String {
    func toInt() -> Int? {
        return Int(self)
    }
} 