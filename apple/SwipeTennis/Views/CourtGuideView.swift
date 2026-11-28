import PDFKit
import SwiftUI

struct CourtGuideView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var page = 0
  @State private var pageCount = 1
  private var url: URL? { Bundle.main.url(forResource: "CourtGuide", withExtension: "pdf") }
  init(initialPage: Int = 0) { _page = State(initialValue: initialPage) }
  var body: some View {
    NavigationStack {
      Group {
        if let url {
          CourtGuidePDF(url: url, page: $page, pageCount: $pageCount)
            .accessibilityIdentifier("illustratedCourtGuide")
        } else {
          ContentUnavailableView("Guide unavailable", systemImage: "doc.richtext",
            description: Text("Swipe toward yellow to receive and white to recover. Tap in position for a split step, volley, or overhead."))
        }
      }.navigationTitle("How to play").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("closeCourtGuide")
          }
          ToolbarItem(placement: .topBarLeading) {
            if let url {
              ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share illustrated guide PDF")
            }
          }
          ToolbarItem(placement: .topBarLeading) {
            NavigationLink { ShotDemoHub() } label: { Image(systemName: "figure.tennis") }
              .accessibilityLabel("Practice shots in the guided demo")
          }
          ToolbarItemGroup(placement: .bottomBar) {
            Button("Previous", systemImage: "chevron.left") { page = max(0, page - 1) }
              .labelStyle(.iconOnly).disabled(page == 0)
            Spacer()
            Text("\(page + 1) of \(pageCount)").font(.subheadline.monospacedDigit())
              .accessibilityLabel("Page \(page + 1) of \(pageCount)")
            Spacer()
            Button("Next", systemImage: "chevron.right") { page = min(pageCount - 1, page + 1) }
              .labelStyle(.iconOnly).disabled(page + 1 >= pageCount).accessibilityIdentifier("nextGuidePage")
          }
        }
    }.presentationDragIndicator(.visible)
  }
}

struct CourtGuideCard: View {
  @State private var isExpanded = false
  @State private var showFullGuide = false
  @State private var showFilm = false
  @State private var page = 0
  private let topics = ["Move, serve & split", "Choose your shot", "Combine your moves", "Attack the short ball",
    "Earn Coachability Points", "Read your opponent", "Scores & a fresh start", "Court markings & out balls"]
  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Button { showFilm = true } label: {
        Label("Watch quick start",systemImage:"play.rectangle")
      }.accessibilityIdentifier("rewatchQuickStart")
      Text("After your serve swipe, the blue ribbon shows your intended bounce. A longer serve swipe sends it deeper. Yellow shows where to meet the ball after the bounce. White keeps you a court length plus four feet from your opponent when space permits. Your player approaches incoming short balls automatically. Tap yellow or swipe forward to commit to the hitting zone, including when it is diagonally ahead. Hiding yellow in Controls keeps the same footwork. Use a fresh swipe to hit. If you arrive just short, your player dives for a defensive lob. Finish your shot swipe before or at the bounce for clean contact. A slightly late swipe has a one-in-three chance of a mishit. Swipe farther for a deeper, harder return. A short swipe plays a softer ball. Flick in one direction to hit. Hold and drag slowly after your shot to move forward, or move sideways or back while receiving. The gold short-ball ring calls you forward. Set your route before the bounce. Watch the energy bars beside the score and run at rally pace to recover. Set your feet early for a stronger drive, or stretch for a shorter block.")
        .font(.subheadline).foregroundStyle(.secondary)
      ForEach(topics.indices, id: \.self) { index in
        Button {
          page = index
          showFullGuide = true
        } label: {
          HStack {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22)
            Text(topics[index])
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
          }
        }.buttonStyle(.plain).accessibilityIdentifier(index == 0 ? "openHomeCourtGuide" : "guideTopic\(index)")
      }
    } label: { Label("How to play", systemImage: "hand.draw") }
      .accessibilityIdentifier("howToPlay")
      .sheet(isPresented: $showFilm) { QuickStartFilm() }
      .sheet(isPresented: $showFullGuide) { CourtGuideView(initialPage: page).id(page) }
  }
}

private struct CourtGuidePDF: UIViewRepresentable {
  let url: URL
  @Binding var page: Int
  @Binding var pageCount: Int

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.backgroundColor = UIColor(TennisTheme.cream)
    view.displayMode = .singlePage
    view.displayDirection = .horizontal
    view.usePageViewController(true, withViewOptions: nil)
    view.document = PDFDocument(url: url)
    view.autoScales = true
    context.coordinator.observe(view)
    DispatchQueue.main.async { pageCount = view.document?.pageCount ?? 1 }
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {
    context.coordinator.parent = self
    guard let document = view.document, let target = document.page(at: page), view.currentPage != target else { return }
    view.go(to: target)
  }

  final class Coordinator {
    var parent: CourtGuidePDF
    private var observer: NSObjectProtocol?
    init(_ parent: CourtGuidePDF) { self.parent = parent }
    func observe(_ view: PDFView) {
      observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
        guard let self, let view, let current = view.currentPage, let document = view.document else { return }
        let index = document.index(for: current)
        if parent.page != index { parent.page = index }
      }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  }
}
