import Foundation

/// Versionszeile fuer die Oberflaeche. Die Werte schreibt `Scripts/bundle.sh`
/// beim Bauen aus `git describe` ins Info.plist; siehe dort.
public enum AppVersion {
    /// Schluessel im Info.plist fuer die volle `git describe`-Ausgabe.
    public static let gitDescriptionKey = "AlarmoohGitDescription"

    /// "Version 0.2.0 (Build 57)", bei einem Build zwischen zwei Tags oder mit
    /// uncommitteten Aenderungen zusaetzlich die `git describe`-Ausgabe — sonst
    /// saehen ein getaggter Stand und drei Commits spaeter gleich aus.
    public static func display(shortVersion: String?, build: String?, gitDescription: String?) -> String {
        guard let shortVersion, !shortVersion.isEmpty else { return "Version unbekannt" }
        var text = "Version \(shortVersion)"
        if let build, !build.isEmpty { text += " (Build \(build))" }
        if let gitDescription, !gitDescription.isEmpty, gitDescription != "v\(shortVersion)" {
            text += " · \(gitDescription)"
        }
        return text
    }

    /// Dasselbe aus einem Bundle gelesen.
    public static func display(for bundle: Bundle) -> String {
        display(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            gitDescription: bundle.object(forInfoDictionaryKey: gitDescriptionKey) as? String
        )
    }
}
