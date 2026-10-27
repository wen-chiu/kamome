import SwiftUI
import UIKit

/// The app as the bundle describes it: the top of About (Chiu 2026-10-26, #293).
///
/// **Read from the bundle, never typed.** The version comes from
/// `Scripts/set-version.sh` and the build number is stamped by every build
/// (`HANDOFF.md`), so a typed copy would be wrong by the next build. The name is
/// the home-screen name, which stays Kamome in both languages (ADR
/// 2026-10-26-zh-hant-uses-one-word-for-each-thing).
struct AppIdentity {
    let name: String
    let version: String
    let build: String
    /// Nil only if the build lost the icon, which `AboutTests` fails on — the
    /// same net `Acknowledgement.text` has.
    let icon: UIImage?

    static var main: AppIdentity { AppIdentity(bundle: .main) }

    init(bundle: Bundle) {
        func value(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        name = value("CFBundleDisplayName").isEmpty ? value("CFBundleName") : value("CFBundleDisplayName")
        version = value("CFBundleShortVersionString")
        build = value("CFBundleVersion")
        // The asset catalogue's icon reaches the bundle as the files Xcode
        // generates from it, named under CFBundleIcons; the last is the largest.
        let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let file = (primary?["CFBundleIconFiles"] as? [String])?.last ?? primary?["CFBundleIconName"] as? String
        icon = file.flatMap { UIImage(named: $0, in: bundle, with: nil) }
    }

    /// 「版本 0.3.1（412）」 / "Version 0.3.1 (412)".
    var versionLine: String {
        String.localizedStringWithFormat(String(localized: "about_version"), version, build)
    }
}

/// Icon, name and version, centred on the list's background rather than in a
/// row: it is the screen's title card, not something to tap.
struct AboutHeader: View {
    let identity: AppIdentity

    var body: some View {
        VStack(spacing: 6) {
            if let icon = identity.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                    .padding(.bottom, 4)
            }
            Text(verbatim: identity.name)
                .font(.title2.bold())
            Text(verbatim: identity.versionLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Someone writing to support can copy it rather than retype it.
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
