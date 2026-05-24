import SwiftUI

struct ContentView: View {
    @StateObject private var ble:          BLEManager
    @StateObject private var classifier:   ClassifierCoordinator
    @StateObject private var profileStore  = PuppyProfileStore()

    init(ble: BLEManager = BLEManager(),
         classifier: ClassifierCoordinator = ClassifierCoordinator()) {
        _ble        = StateObject(wrappedValue: ble)
        _classifier = StateObject(wrappedValue: classifier)
    }

    var body: some View {
        TabView {
            // -- User Mode tab --
            NavigationStack {
                UserModeView()
                    .toolbar { connectionToolbarItem }
            }
            .tabItem {
                Label("My Dog", systemImage: "pawprint.fill")
            }

            // -- Puppy Profile tab --
            NavigationStack {
                PuppyProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "dog.fill")
            }

            // -- Dev Mode tab --
            NavigationStack {
                DevModeView()
                    .toolbar { connectionToolbarItem }
            }
            .tabItem {
                Label("Dev", systemImage: "waveform.badge.magnifyingglass")
            }
        }
        .onAppear {
            ble.onAudioPacket = { [weak classifier] data in classifier?.handle(audioPacket: data) }
            ble.onIMUPacket   = { [weak classifier] data in classifier?.handle(imuPacket: data) }
        }
        .environmentObject(ble)
        .environmentObject(classifier)
        .environmentObject(profileStore)
    }

    // MARK: - Shared connection button (shown in both tabs' nav bars)

    @ToolbarContentBuilder
    private var connectionToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ble.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Button {
                    if ble.isConnected { ble.disconnect() } else { ble.connect() }
                } label: {
                    Text(ble.isConnected ? "Disconnect" : "Connect")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            (ble.isConnected ? Color.red : Color.green).opacity(0.15)
                        )
                        .foregroundStyle(ble.isConnected ? .red : .green)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

#Preview {
    ContentView(
        ble: BLEManager(forPreview: true),
        classifier: ClassifierCoordinator(forPreview: true)
    )
}
