import SwiftUI

/// A detail screen's map header (S15 #538, S20 #570), after Apple Fitness's workout detail: a map
/// behind the list that runs under the top safe area, half the screen tall, its bottom
/// `Spacing.mapHeaderFade` fading to the page. It rides up with the list and fades as it goes,
/// stretches from the top when the rider pulls down past it, and the screen's title moves into the
/// toolbar once it scrolls under it.
///
/// The pieces a screen puts together:
/// - `MapHeaderTapRow`, the list's first row: clear, over the map, and what opens the map sheet
/// - `.mapHeader(…)` on the list, which draws the map behind it and follows the scroll
/// - `.tracksTitleUnderToolbar(…)` on the title block, and `MapHeaderToolbarTitle` in the bar
extension View {
    /// Draws `header` behind this list as the screen's map header. `hasHeader` keeps the room under
    /// the top safe area; `drawsMap` draws the map in it, fading in when it turns true.
    func mapHeader<Header: View>(hasHeader: Bool, drawsMap: Bool, height: CGFloat, toolbarBottom: CGFloat,
                                 header: Header) -> some View {
        modifier(MapHeaderBackground(hasHeader: hasHeader, drawsMap: drawsMap, height: height,
                                     toolbarBottom: toolbarBottom, header: header))
    }

    /// Sets `isUnder` whenever this view's bottom passes under the toolbar or back out. The answer,
    /// not the frame, so the binding is written only when it flips.
    func tracksTitleUnderToolbar(_ toolbarBottom: CGFloat, isUnder: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            MapHeaderChrome.isTitleUnderToolbar(titleBottom: proxy.frame(in: .global).maxY,
                                                toolbarBottom: toolbarBottom)
        } action: { isUnder.wrappedValue = $0 }
    }
}

/// The list's first row over the map header: clear, so the map behind shows through, and the tap
/// that opens the map sheet. The title block starts under it, where the map starts to fade.
struct MapHeaderTapRow: View {
    /// The header's full height. The row stops where the fade starts.
    let height: CGFloat
    /// Off until there is a map to open.
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(height: height - Spacing.mapHeaderFade)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHidden(!isEnabled)
        .accessibilityLabel("Route map")
        .accessibilityHint("Opens the map full screen")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The screen's title in the bar's `principal` slot, in once the title block has scrolled under the
/// bar: a fade and a short rise, as S14's inline title comes in when its large title scrolls away.
/// Always laid out, so the bar never resizes the item — inserting it revealed it from the centre.
struct MapHeaderToolbarTitle: View {
    let title: String
    let isShown: Bool

    var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : Spacing.sm)
            .animation(.smooth(duration: 0.25), value: isShown)
            .accessibilityHidden(!isShown)
    }
}

/// The map behind the list, and the scroll that moves it. A modifier holding the offset as its own
/// state, so a scroll frame re-runs this body alone: the list is its `content`, which a change here
/// doesn't rebuild. View state, not store state: it changes every frame of a scroll and only the
/// chrome reads it.
private struct MapHeaderBackground<Header: View>: ViewModifier {
    /// The list runs under the top safe area, with room kept for the header.
    let hasHeader: Bool
    /// The map's content has loaded, so the map draws in that room.
    let drawsMap: Bool
    let height: CGFloat
    let toolbarBottom: CGFloat
    let header: Header

    /// How far the list has scrolled (`MapHeaderChrome`).
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    if drawsMap {
                        MapHeaderFrame(height: height, toolbarBottom: toolbarBottom, offset: scrollOffset,
                                       content: header)
                            .transition(.opacity)
                    }
                }
                // In with the map's content rather than popping in over the room kept for it.
                .animation(.easeIn(duration: 0.25), value: drawsMap)
                .ignoresSafeArea()
            }
            // Under the top safe area only with a map to run under it. Without one, the title
            // block is the first thing below the toolbar.
            .ignoresSafeArea(edges: hasHeader ? .top : [])
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrollOffset = offset
            }
    }
}

/// The map header's frame: pinned to the top of the screen, `height` tall, its bottom
/// `Spacing.mapHeaderFade` fading to the page. It rides up with the list and fades as it goes,
/// and stretches from the top when the rider pulls down past it.
private struct MapHeaderFrame<Content: View>: View {
    let height: CGFloat
    let toolbarBottom: CGFloat
    let offset: CGFloat
    let content: Content

    var body: some View {
        content
            // The route fits between the toolbar and the start of the title area (UX.md §S15).
            .safeAreaPadding(.top, toolbarBottom)
            .safeAreaPadding(.bottom, Spacing.mapHeaderFade)
            .frame(height: height)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Spacing.mapHeaderFade)
                }
            }
            .scaleEffect(MapHeaderChrome.mapStretch(offset: offset, mapHeight: height), anchor: .top)
            .offset(y: -max(offset, 0))
            .opacity(MapHeaderChrome.mapOpacity(offset: offset, mapHeight: height, fade: Spacing.mapHeaderFade))
            // The clear row in the list above it takes the taps.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

/// A list over a stand-in map, to see the fade, the stretch and the title move into the bar.
private struct MapHeaderPreview: View {
    var drawsMap = true
    @State private var isTitleUnderToolbar = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let height = MapHeaderChrome.mapHeight(
                    screenHeight: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                )
                List {
                    Section {
                        MapHeaderTapRow(height: height, isEnabled: drawsMap) {}
                        Text("Summit Climb")
                            .font(.title)
                            .tracksTitleUnderToolbar(proxy.safeAreaInsets.top, isUnder: $isTitleUnderToolbar)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    Section("Rows") {
                        ForEach(1..<30) { Text("Row \($0)") }
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .mapHeader(hasHeader: true, drawsMap: drawsMap, height: height,
                           toolbarBottom: proxy.safeAreaInsets.top, header: Color.cyPrimary)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        MapHeaderToolbarTitle(title: "Summit Climb", isShown: isTitleUnderToolbar)
                    }
                }
            }
        }
    }
}

#Preview("Map header") {
    MapHeaderPreview()
}

/// The room kept while the map's content loads.
#Preview("Map header — loading") {
    MapHeaderPreview(drawsMap: false)
}

#Preview("Map header — dark") {
    MapHeaderPreview()
        .preferredColorScheme(.dark)
}
