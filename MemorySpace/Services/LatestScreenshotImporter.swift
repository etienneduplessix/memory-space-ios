import Foundation
import Photos

enum LatestScreenshotImporter {
    enum ImportError: LocalizedError {
        case permissionDenied
        case noScreenshotFound
        case imageUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Allow Full Photo Access to automatically import the screenshot taken by the Action Button."
            case .noScreenshotFound:
                "No recent screenshot was found in Photos."
            case .imageUnavailable:
                "The latest screenshot could not be read."
            }
        }
    }

    static func loadLatestScreenshot() async throws -> Data {
        let authorization = await requestPhotoAuthorization()
        guard authorization == .authorized else {
            throw ImportError.permissionDenied
        }

        // Shortcuts' "Save to Photo Album" action stores a screenshot as a regular
        // image in Recents, not always with Photos' screenshot media subtype.
        // The shortcut runs this importer immediately after saving, so the newest
        // image is the one it just captured.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let results = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = results.firstObject else {
            throw ImportError.noScreenshotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let requestOptions = PHImageRequestOptions()
            requestOptions.isNetworkAccessAllowed = false
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.version = .current

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImportError.imageUnavailable)
                }
            }
        }
    }

    private static func requestPhotoAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
