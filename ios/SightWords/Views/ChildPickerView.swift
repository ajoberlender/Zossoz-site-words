import SwiftUI

struct ChildPickerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthService
    @State private var selected: Child?
    @State private var showAdd = false
    @State private var showGate = false
    @State private var showAccount = false
    @State private var gatePassed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Who's reading?").bigFont(36).padding(.top, 16)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(store.children) { child in
                            Button { selected = child } label: {
                                VStack(spacing: 8) {
                                    Text(child.avatar).font(.system(size: 72))
                                    Text(child.name).font(.title2.bold()).foregroundStyle(Theme.ink)
                                    Text("⭐ \(child.stars)  🔥 \(child.streakDays)").font(.callout).foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(child.name), \(child.stars) stars, \(child.streakDays) day streak")
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showGate = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.mint)
                                Text("Add a reader").font(.headline).foregroundStyle(Theme.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 190)
                            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.grape.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8])))
                        }
                        .buttonStyle(.plain)
                    }
                    if let err = store.lastSyncError {
                        Label("Offline — progress is saved on this device and will sync later.", systemImage: "icloud.slash")
                            .font(.footnote).foregroundStyle(.secondary).help(err)
                    }
                }
                .padding(24)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: { Image(systemName: "gearshape.fill") }.accessibilityLabel("Account")
                }
            }
            .navigationDestination(item: $selected) { child in HomeView(childID: child.id) }
            .sheet(isPresented: $showGate, onDismiss: {
                if gatePassed { gatePassed = false; showAdd = true }
            }) {
                GrownUpGate { gatePassed = true }
            }
            .sheet(isPresented: $showAdd) { AddChildView() }
            .sheet(isPresented: $showAccount) { AccountGateSheet() }
        }
    }
}

private struct AccountGateSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var passed = false

    var body: some View {
        if passed {
            NavigationStack {
                List {
                    if case .signedIn(let u) = auth.state { Section("Signed in") { Text(u.email) } }
                    Section("Sync") {
                        Button(store.syncing ? "Syncing…" : "Sync now") { Task { await store.sync() } }.disabled(store.syncing)
                        if let d = store.lastSyncDate { Text("Last synced \(d.formatted(.relative(presentation: .named)))").font(.footnote) }
                        if let e = store.lastSyncError { Text(e).font(.footnote).foregroundStyle(.red) }
                    }
                    Section { Button("Sign out", role: .destructive) { Task { await auth.signOut() } } }
                }
                .navigationTitle("Account")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            GrownUpGate(dismissOnPass: false) { passed = true }
        }
    }
}

struct AddChildView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = Theme.avatars[0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Reader's name", text: $name) }
                Section("Pick a buddy") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))]) {
                        ForEach(Theme.avatars, id: \.self) { a in
                            Button { avatar = a } label: {
                                Text(a).font(.system(size: 40)).padding(6)
                                    .background(a == avatar ? Theme.sun.opacity(0.5) : .clear, in: Circle())
                                    .overlay(Circle().stroke(a == avatar ? Theme.grape : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Buddy \(a)")
                            .accessibilityAddTraits(a == avatar ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("New reader")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addChild(name: name.trimmingCharacters(in: .whitespaces), avatar: avatar)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
