import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(nsImage: Self.appIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)

            Text(AppAboutInfo.appName)
                .font(.system(size: 20, weight: .semibold))

            Text(AppAboutInfo.versionLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(AppAboutInfo.copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text(L10n.tr("about.author", AppAboutInfo.author))
                    .font(.system(size: 12))

                Link(AppAboutInfo.githubDisplay, destination: AppAboutInfo.githubURL)
                    .font(.system(size: 12))
            }
            .padding(.top, 2)

            Divider()
                .frame(maxWidth: 280)

            VStack(spacing: 4) {
                Text(L10n.tr("about.builtWith"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(AppAboutInfo.techStack)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// LSUIElement apps often leave `NSApp.applicationIconImage` as the generic
    /// icon even when `AppIcon.appiconset` is present — load catalog / icns /
    /// workspace icon explicitly (EggplantShot About used applicationIconImage
    /// and worked; Recorder was still showing the default).
    private static var appIconImage: NSImage {
        if let named = NSImage(named: "AppIcon"), named.size.width > 0 {
            return named
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let fromFile = NSImage(contentsOf: url)
        {
            return fromFile
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

enum AppAboutInfo {
    static let author = "uniquejava"
    static let githubURL = URL(string: "https://github.com/uniquejava/EggplantRecorder")!
    static let githubDisplay = "github.com/uniquejava/EggplantRecorder"
    static let techStack = """
    SwiftUI + AppKit · ScreenCaptureKit
    AVAssetWriter dual audio · macOS 15+
    """

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "EggplantRecorder"
    }

    static var versionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return L10n.tr("about.version", short, build)
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 uniquejava. All rights reserved."
    }
}
