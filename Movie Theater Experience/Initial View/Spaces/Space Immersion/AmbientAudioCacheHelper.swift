import Foundation

enum AmbientAudioCacheHelper {
    private static var cacheDirectory: URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate caches directory for ambient audio")
        }
        let audioCacheDirectory = cachesDirectory.appendingPathComponent("Spaces/ambient_audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: audioCacheDirectory.path) {
            try? FileManager.default.createDirectory(at: audioCacheDirectory, withIntermediateDirectories: true)
        }
        return audioCacheDirectory
    }
    
    static func cacheURL(for remoteURL: URL) -> URL {
        cacheDirectory.appendingPathComponent(sanitizedFileName(for: remoteURL))
    }
    
    static func sanitizedFileName(for remoteURL: URL) -> String {
        let lastComponent = remoteURL.lastPathComponent
        let baseName: String
        if let queryIndex = lastComponent.firstIndex(of: "?") {
            baseName = String(lastComponent[..<queryIndex])
        } else {
            baseName = lastComponent
        }
        let sanitized = baseName.replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }
}
