import Foundation
import AudioToolbox

struct ResolvedSound {
    let url: URL?
    let systemID: SystemSoundID
}

enum SoundResolver {
    /// Resolve a selection into either a bundled URL (preferred) or a fallback system sound ID.
    /// - Parameters:
    ///   - selection: Int chosen by the user. 0 means try bundled file first, otherwise treat as a system sound ID.
    ///   - isRest: If true, try a rest-specific bundled filename first.
    /// - Returns: ResolvedSound indicating either a URL to play via AVAudioPlayer, or a SystemSoundID.
    static func resolve(selection: Int, isRest: Bool) -> ResolvedSound {
        // If selection == 0, attempt to use a bundled CAF first.
        if selection == 0 {
            if let url = bundledURL(isRest: isRest) {
                return ResolvedSound(url: url, systemID: 0)
            }
            // Fall back to a reasonable default system sound if no file is bundled
            return ResolvedSound(url: nil, systemID: 1007) // Tock
        }
        // Non-zero selection: treat as system sound ID
        return ResolvedSound(url: nil, systemID: SystemSoundID(selection))
    }

    /// Looks for a bundled sound file. For work: bell.caf, for rest: rest.caf (if available).
    private static func bundledURL(isRest: Bool) -> URL? {
        let candidates: [String] = isRest ? ["rest", "bell"] : ["bell", "rest"]
        let bundle = Bundle.main
        for name in candidates {
            if let url = bundle.url(forResource: name, withExtension: "caf") {
                return url
            }
        }
        return nil
    }
}
