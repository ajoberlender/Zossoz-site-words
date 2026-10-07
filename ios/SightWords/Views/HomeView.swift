import SwiftUI

struct HomeView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @State private var playing = false
    @State private var showStories = false
    @State private var showGate = false
    @State private var showParent = false

    private var child: Child? { store.child(childID) }

    var body: some View {
        if let child {
            ScrollView {
                VStack(spacing: 20) {
                    header(child)
                    BigButton(title: "Let's read!", systemImage: "play.fill", color: Theme.mint) { playing = true }
                    HStack(spacing: 14) {
                        BigButton(title: "Stories", systemImage: "book.fill", color: Theme.sun) { showStories = true }
                        BigButton(title: "Grown-ups", systemImage: "lock.fill", color: Theme.ink.opacity(0.75)) { showGate = true }
                    }
                    stageMap(child)
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $playing) { SessionView(childID: childID) }
            .fullScreenCover(isPresented: $showStories) { StoriesView(childID: childID) }
            .sheet(isPresented: $showGate) { GrownUpGate { showParent = true } }
            .sheet(isPresented: $showParent) { ParentView(childID: childID) }
        } else {
            ContentUnavailableView("Reader not found", systemImage: "person.slash")
        }
    }

    private func header(_ c: Child) -> some View {
        HStack(spacing: 16) {
            Text(c.avatar).font(.system(size: 64))
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi, \(c.name)!").font(Theme.big(30)).foregroundStyle(Theme.ink)
                Text("⭐ \(c.stars)   🔥 \(c.streakDays) day\(c.streakDays == 1 ? "" : "s")").font(.title3.bold()).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func stageMap(_ c: Child) -> some View {
        VStack(spacing: 12) {
            ForEach(Curriculum.stages) { stage in
                let stat = store.masteredCount(childID: c.id, stage: stage.id)
                let locked = stage.id > c.currentStage
                HStack(spacing: 14) {
                    Text(locked ? "🔒" : stage.emoji).font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title).font(.headline).foregroundStyle(Theme.ink)
                        Text(stage.blurb).font(.footnote).foregroundStyle(.secondary)
                        ProgressView(value: Double(stat.seen), total: Double(max(stat.total, 1)))
                            .tint(stage.id == c.currentStage ? Theme.grape : Theme.mint)
                    }
                }
                .padding(14)
                .background(.white.opacity(locked ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(stage.id == c.currentStage ? Theme.grape : .clear, lineWidth: 3))
                .opacity(locked ? 0.7 : 1)
            }
        }
    }
}
