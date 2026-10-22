import SwiftUI
import WidgetKit

// Must match `widgetAppGroupId` / `widgetName` in
// lib/features/platform/widget_data.dart. The app writes `title`, `detail`
// and `uri` with home_widget; `updateWidget(iOSName:)` reloads this kind.
private let appGroupId = "group.dev.corplex.app"
private let widgetKind = "CorplexWidget"
private let newNoteURL = widgetLink(URL(string: "corplex://new-note")!)

/// home_widget on iOS only reports a tap to the app (`widgetClicked`) when
/// the URL carries a `homeWidget` query item; without it the app opens
/// and nothing happens. The Dart side ignores the extra item.
private func widgetLink(_ url: URL) -> URL {
  guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
  var items = parts.queryItems ?? []
  if !items.contains(where: { $0.name == "homeWidget" }) {
    items.append(URLQueryItem(name: "homeWidget", value: nil))
  }
  parts.queryItems = items
  return parts.url ?? url
}

/// The widget's few fixed texts, English or German by the system language
/// (a table in code: the extension has no strings files).
private let germanTexts = [
  "Continue reading": "Weiterlesen",
  "Open a paper to pick up where you left off.":
    "Paper öffnen und dort weiterlesen, wo du aufgehört hast.",
  "New note": "Neue Notiz",
  "Pick up your paper where you left off, or start a note.":
    "Paper dort weiterlesen, wo du aufgehört hast, oder eine Notiz beginnen.",
]

private func tr(_ english: String) -> String {
  let german = Locale.preferredLanguages.first?.hasPrefix("de") ?? false
  return german ? (germanTexts[english] ?? english) : english
}

struct ReadingEntry: TimelineEntry {
  let date: Date
  let title: String?
  let detail: String?
  let url: URL?
}

struct ReadingProvider: TimelineProvider {
  func placeholder(in context: Context) -> ReadingEntry {
    ReadingEntry(date: Date(), title: "Attention Is All You Need", detail: "p. 4", url: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
    // The app reloads the timeline whenever the data changes.
    completion(Timeline(entries: [load()], policy: .never))
  }

  private func load() -> ReadingEntry {
    let d = UserDefaults(suiteName: appGroupId)
    func text(_ key: String) -> String? {
      guard let s = d?.string(forKey: key), !s.isEmpty else { return nil }
      return s
    }
    return ReadingEntry(
      date: Date(),
      title: text("title"),
      detail: text("detail"),
      url: text("uri").flatMap(URL.init(string:)).map(widgetLink))
  }
}

// Sage on warm paper, matching lib/theme/app_theme.dart (light and dark).
private extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
  }

  static let paper = adaptive(light: 0xF7F6F1, dark: 0x161917)
  static let ink = adaptive(light: 0x282C28, dark: 0xE2E5DF)
  static let inkSoft = adaptive(light: 0x5E655E, dark: 0xB3BAB1)
  static let sage = adaptive(light: 0x55715A, dark: 0xA9C4A5)
  static let sageWash = adaptive(light: 0xD9E5D4, dark: 0x384C3B)
  static let onSage = adaptive(light: 0xFFFFFF, dark: 0x1B3120)
}

struct CorplexWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ReadingEntry

  private var destination: URL { entry.url ?? newNoteURL }

  var body: some View {
    Group {
      if family == .systemMedium {
        HStack(alignment: .center, spacing: 14) {
          reading
          Spacer(minLength: 0)
          newNoteButton
        }
      } else {
        reading
      }
    }
    .padding(2)
    .widgetURL(destination)
    .containerBackgroundCompat(Color.paper)
  }

  private var reading: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let title = entry.title {
        Text(verbatim: tr("Continue reading"))
          .font(.caption2.weight(.medium))
          .foregroundColor(.sage)
        Text(title)
          .font(.system(.subheadline, design: .serif).weight(.semibold))
          .foregroundColor(.ink)
          .lineLimit(family == .systemSmall ? 4 : 3)
        if let detail = entry.detail {
          Text(detail)
            .font(.caption)
            .foregroundColor(.inkSoft)
        }
      } else {
        Text("Corplex")
          .font(.system(.headline, design: .serif).weight(.semibold))
          .foregroundColor(.ink)
        Text(verbatim: tr("Open a paper to pick up where you left off."))
          .font(.caption)
          .foregroundColor(.inkSoft)
          .lineLimit(3)
      }
      if family == .systemSmall { Spacer(minLength: 0) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var newNoteButton: some View {
    Link(destination: newNoteURL) {
      Label(tr("New note"), systemImage: "square.and.pencil")
        .font(.footnote.weight(.semibold))
        .foregroundColor(.onSage)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.sage))
    }
  }
}

private extension View {
  /// `containerBackground` is iOS 17+; older systems take a plain background.
  @ViewBuilder
  func containerBackgroundCompat(_ color: Color) -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(color, for: .widget)
    } else {
      self.padding(12).background(color)
    }
  }
}

@main
struct CorplexWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: ReadingProvider()) { entry in
      CorplexWidgetView(entry: entry)
    }
    .configurationDisplayName("Corplex")
    .description(tr("Pick up your paper where you left off, or start a note."))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
