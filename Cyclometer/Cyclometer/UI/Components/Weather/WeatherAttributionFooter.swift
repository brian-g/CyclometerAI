import SwiftUI

/// What WeatherKit's terms require under its data (#148, #149): the Apple Weather mark, in its
/// light or dark form, and a link to the legal attribution page. The service's name stands in for
/// the mark until it loads, or if it can't.
///
/// "Legal" sits on the mark's baseline. The mark is cropped tight to its glyphs, and "Weather" has no
/// descenders, so the image's bottom edge is its baseline.
struct WeatherAttributionFooter: View {
    let attribution: WeatherSourceAttribution

    @Environment(\.colorScheme) private var colorScheme
    /// Grows with Dynamic Type, so the mark keeps its size beside "Legal".
    @ScaledMetric(relativeTo: .caption) private var markHeight = Spacing.weatherMark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                image.resizable().scaledToFit()
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            } placeholder: {
                Text(attribution.serviceName)
            }
            .frame(height: markHeight)
            .accessibilityLabel(attribution.serviceName)
            Link("Legal", destination: attribution.legalPageURL)
                .accessibilityLabel("\(attribution.serviceName) legal attribution")
        }
        .font(.caption)
    }
}

// MARK: - Previews

#Preview("Light") {
    List {
        Section {
            Text("Rows")
        } header: {
            Text("Weather")
        } footer: {
            WeatherAttributionFooter(attribution: .fixture)
        }
    }
}

#Preview("Dark") {
    List {
        Section {
            Text("Rows")
        } header: {
            Text("Weather")
        } footer: {
            WeatherAttributionFooter(attribution: .fixture)
        }
    }
    .preferredColorScheme(.dark)
}
