import KamomeConfig
import SwiftUI

/// About, in the order Chiu decided on 2026-10-26 (#293, ADR
/// `2026-10-26-about-opens-with-the-app-and-speaks-plainly`): who the app is,
/// what leaves the device in plain words, a way to reach the developer and to
/// rate the app, then what is owed to others. It used to open on the terrain
/// licences, with no name, version or contact anywhere on it.
///
/// **Attribution is a licence condition, not copy.** Geoapify attribution is
/// mandatory on the free plan, in the format "Powered by Geoapify" with a link,
/// and OpenStreetMap attribution is always required. The 2026-10-26 order moved
/// the credits down the screen; every word of them is unchanged.
///
/// ⚠️ **Amended 2026-09-12, and this screen keeps everything it carries.** Chiu
/// decided 2026-08-17 that attribution lives in the app's *interface* and never
/// in the rendered film (`Docs/pre-launch.md`). That was decided when the film's
/// imagery was Apple's; a film drawn on OSM-derived tiles is a **produced work**
/// under ODbL and carries its own map credit now (ADR 2026-09-12 (b),
/// `RecapMapAttribution`). Two things did **not** change: Geoapify's attribution
/// is owed for the *routing service* and belongs here, not in a film; and the
/// film draws nothing at all while its substrate is Apple's.
///
/// **The privacy notice is an honest declaration** (ADR 2026-08-20 (c)), so
/// every sentence was checked against the code rather than against an intention.
/// This screen carries the plain half; the payloads, retention and the server's
/// detail are one row away, on `PrivacyDetailView`.
///
/// **The same strings are the first-run notice's strings** (`FirstRunNoticeView`,
/// ADR 2026-09-05 (b)) — one source, so the screen a user can always come back to
/// and the one-time telling cannot drift apart.
///
/// **The wording is Chiu's**, approved as one table on 2026-10-28 (PR #323, #118).
struct AboutView: View {
    /// Read, not hardcoded: the notice states these two numbers as fact.
    let matching: TrackingConfig.Matching
    @Environment(\.dismiss) private var dismiss
    /// The diagnostics file being shared; its sheet hangs on the list (#189).
    @State private var diagnosticsFile: DiagnosticsFile?

    /// Licence targets, deliberately not in `TrackingConfig.json`. Rule 7 governs
    /// *tunables*; changing either of these is a licence breach, not a tuning
    /// decision, and a key someone may edit is the wrong shape for that.
    private static let geoapify = URL(string: "https://www.geoapify.com/")!
    private static let openStreetMap = URL(string: "https://www.openstreetmap.org/copyright")!
    private static let terrainTiles = URL(string: "https://registry.opendata.aws/terrain-tiles/")!
    /// The hosted policy App Store Connect points at. Guideline 5.1.1(i) wants
    /// it reachable inside the app as well as in the store listing (#150). Not a
    /// tunable either: it must be the same page as the store's, and
    /// `Scripts/release/check-attribution.sh` fails if it disappears.
    private static let privacyPolicy = URL(string: "https://wen-chiu.github.io/kamome-site/privacy/")!
    /// Where 「意見回饋」 goes (Chiu 2026-10-26, #293): the site's support page,
    /// which is also the store listing's support URL.
    static let support = URL(string: "https://wen-chiu.github.io/kamome-site/support/")!
    /// The App Store's own write-a-review sheet. 6813758768 is Kamome's Apple ID
    /// in App Store Connect (Chiu 2026-10-27) — not the bundle id, not the SKU.
    static let writeReview = URL(string: "https://apps.apple.com/app/id6813758768?action=write-review")!

    var body: some View {
        NavigationStack {
            List {
                ForEach(AboutSection.allCases, id: \.self) { section in
                    content(of: section)
                }
            }
            .diagnosticsShareSheet($diagnosticsFile)
            .navigationTitle("about_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("about_close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func content(of section: AboutSection) -> some View {
        switch section {
        case .app: Section { AboutHeader(identity: .main) }
        case .privacy: privacySection
        case .support: supportSection
        case .diagnostics: DiagnosticsSection(file: $diagnosticsFile)
        case .credits: attributionSection
        case .licences: acknowledgementsSection
        }
    }

    /// The plain half of the notice: what stays, who is asked for what, what
    /// the reader controls. The technical half is behind 「詳細說明」.
    private var privacySection: some View {
        Section {
            Text("privacy_intro")
            // Which parties handle a journey's coordinates on the way to the
            // roads — read off the config, so the config flip changes the
            // sentence with it (`PrivacyNoticeCopy`).
            Text(LocalizedStringKey(PrivacyNoticeCopy.hopKey(for: matching)))
            Text("privacy_control")
            Text("privacy_share")
            NavigationLink {
                PrivacyDetailView(matching: matching)
            } label: {
                Text("privacy_details")
            }
            Link(destination: Self.privacyPolicy) {
                linkRow("privacy_policy_link")
            }
        } header: {
            Text("privacy_header")
        }
        .font(.callout)
    }

    /// Feedback, then rating — the order Chiu gave.
    private var supportSection: some View {
        Section {
            Link(destination: Self.support) {
                linkRow("about_feedback")
            }
            Link(destination: Self.writeReview) {
                linkRow("about_rate")
            }
        }
    }

    /// S2. The rows are the obligation; the footer is the explanation, and
    /// the obligation does not depend on it.
    ///
    /// **Quiet, not hidden** (Chiu 2026-10-28, PR #323): footnote type in the
    /// secondary text colour instead of accent-teal body text, and still links.
    /// Only the look changed; every word is the licence's.
    private var attributionSection: some View {
        Section {
            // "Powered by Geoapify" is the format the free plan requires, so it
            // is the same string in both languages — a translated brand
            // attribution would no longer be the required format.
            Link(destination: Self.geoapify) {
                creditRow("attribution_geoapify")
            }
            Link(destination: Self.openStreetMap) {
                creditRow("attribution_osm")
            }
            Link(destination: Self.terrainTiles) {
                creditRow("attribution_terrain")
            }
        } header: {
            Text("attribution_header")
        } footer: {
            Text("attribution_note")
        }
    }

    /// The software licences the app's own contents oblige it to reproduce,
    /// in full rather than linked (ADR 2026-09-12 (c)). Last, because it is the
    /// section a reader is least likely to have come for.
    private var acknowledgementsSection: some View {
        Section {
            ForEach(Acknowledgement.all) { library in
                NavigationLink {
                    LicenceTextView(acknowledgement: library)
                } label: {
                    LabeledContent(library.name, value: "\(library.version) · \(library.licence)")
                }
            }
        } header: {
            Text("acknowledgements_header")
        } footer: {
            Text("acknowledgements_note")
        }
    }

    private func linkRow(_ key: LocalizedStringKey) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }

    /// A credit: the same row, quieter. The colour is the system's secondary
    /// label as a concrete colour, because inside a `Link` the hierarchical
    /// `.secondary` is read off the link's tint and comes out pale teal.
    private func creditRow(_ key: LocalizedStringKey) -> some View {
        HStack {
            Text(key)
            Spacer()
            Image(systemName: "arrow.up.forward.square")
        }
        .font(.footnote)
        .foregroundStyle(Color(uiColor: .secondaryLabel))
    }
}

/// About's sections, top to bottom. Chiu 2026-10-26 (#293): name, icon and
/// version → privacy in plain words → feedback → rating → map and terrain
/// credits → open-source licences. `AboutTests` holds the order.
///
/// Diagnostics was not in that list; it sits after rating because the file it
/// exports is what a tester sends along with feedback, and before the credits so
/// the screen's last two sections are the ones owed to others.
enum AboutSection: CaseIterable {
    case app
    case privacy
    /// Feedback, then rating.
    case support
    case diagnostics
    case credits
    case licences
}
