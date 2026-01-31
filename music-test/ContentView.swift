import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import CoreMotion

// MARK: - Manager Ruchu (Pijana Okładka)
class MotionManager: ObservableObject {
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    private let manager = CMMotionManager()

    init() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let self = self, let motion = motion else { return }
                self.pitch = motion.attitude.pitch
                self.roll = motion.attitude.roll
            }
        }
    }
}

// MARK: - Systemowy Suwak (Dla tych co lubią sąsiadów denerwować)
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsRouteButton = true
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = .systemPink
        }
        return volumeView
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Wizualizator Dźwięku (Skaczące Kreski)
struct AudioVisualizer: View {
    var power: Float
    var isPlaying: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<15) { _ in
                let heightMultiplier = CGFloat.random(in: 0.6...1.2)
                let barHeight = isPlaying ? max(4, CGFloat(power) * 70 * heightMultiplier) : 4
                
                Capsule()
                    .frame(width: 4, height: barHeight)
                    .foregroundColor(.pink)
                    .shadow(color: .pink.opacity(0.3), radius: 2)
            }
        }
        .frame(height: 70)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: power)
    }
}

// MARK: - Manager Audio (Serce i Płuca aplikacji)
class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    struct Track: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let artist: String
        let fileName: String
    }
    
    enum RepeatMode { case none, one, all }

    @Published var playlist: [Track] = []
    @Published var currentIndex: Int = 0
    var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var repeatMode: RepeatMode = .none
    @Published var audioPower: Float = 0.0

    var currentTrack: Track? {
        guard playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    private var timer: AnyCancellable?

    override init() {
        super.init()
        self.playlist = [
            Track(title: "taobao", artist: "yungmioder, mlodygolab", fileName: "taobao"),
            Track(title: "morenka", artist: "yungmioder, mlodygolab, ava7ktp, got", fileName: "morenka"),
            Track(title: "shortnuke", artist: "yungmioder, mlodygolab, olliethawave", fileName: "shortnuke"),
            Track(title: "riot games", artist: "yungmioder, mlodygolab", fileName: "riot_games"),
            Track(title: "glowa", artist: "yungmioder, mlodygolab, plnjosh", fileName: "glowa"),
            Track(title: "niepokonani", artist: "yungmioder, mlodygolab, plnjosh, gbpjohnn", fileName: "niepokonani"),
            Track(title: "hvh", artist: "yungmioder, mlodygolab", fileName: "hvh")
        ]
        setupRemoteCommands()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            switch repeatMode {
            case .none: 
                if currentIndex < playlist.count - 1 { nextTrack() } else { isPlaying = false }
            case .one: 
                startNewPlayer()
            case .all: 
                nextTrack()
            }
        }
    }

    func playPause() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                timer?.cancel()
            } else {
                player.play()
                isPlaying = true
                startTimer()
            }
        } else {
            startNewPlayer()
        }
        updateNowPlaying()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func startNewPlayer() {
        guard let track = currentTrack else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
        try? session.setActive(true)

        guard let path = Bundle.main.path(forResource: track.fileName, ofType: "mp3") else {
            print("❌ Brak pliku: \(track.fileName).mp3")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            audioPlayer?.delegate = self
            audioPlayer?.isMeteringEnabled = true
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        } catch {
            print("Błąd audio: \(error.localizedDescription)")
        }
    }

    func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                player.updateMeters()
                let power = player.averagePower(forChannel: 0)
                self.audioPower = self.normalizePower(power)
            }
    }
    
    private func normalizePower(_ power: Float) -> Float {
        guard power.isFinite else { return 0.0 }
        let minDb: Float = -80.0
        if power < minDb { return 0.0 }
        let res = (power - minDb) / -minDb
        return pow(res, 2.0)
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
        commandCenter.pauseCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in self?.nextTrack(); return .success }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in self?.previousTrack(); return .success }
    }

    func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? "Brak nuty"
        info[MPMediaItemPropertyArtist] = currentTrack?.artist ?? "Brak artysty"
        if let player = audioPlayer {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        }
        if let image = UIImage(named: "okladka") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func nextTrack() {
        currentIndex = (currentIndex + 1) % playlist.count
        startNewPlayer()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func previousTrack() {
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        startNewPlayer()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Widok Główny
struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var motionManager = MotionManager()
    @State private var showInfo = false

    var body: some View {
        ZStack {
            Image("okladka")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .blur(radius: 50)
                .opacity(0.4)
            
            Color.black.opacity(0.7).ignoresSafeArea()
            
            VStack(spacing: 20) {
                HStack {
                    Button(action: {}) { Image(systemName: "square.and.arrow.up") }
                    Spacer()
                    Text("ATHC PREMIUM PLAYER").font(.system(size: 14, weight: .black)).tracking(3).foregroundColor(.pink)
                    Spacer()
                    Button(action: { showInfo = true }) { Image(systemName: "info.circle.fill") }
                }
                .foregroundColor(.white)
                .padding(.top, 10)

                Spacer()

                Image("okladka")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(25)
                    .shadow(color: .pink.opacity(0.5), radius: 30)
                    .offset(x: CGFloat(motionManager.roll * 25), y: CGFloat(motionManager.pitch * 25))
                    .rotation3DEffect(.degrees(motionManager.roll * 12), axis: (x: 0, y: 1, z: 0))
                    .padding(20)

                VStack(spacing: 8) {
                    Text(audioManager.currentTrack?.title ?? "Wybierz track")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(audioManager.currentTrack?.artist ?? "Artysta")
                        .font(.title3)
                        .foregroundColor(.pink.opacity(0.8))
                }

                AudioVisualizer(power: audioManager.audioPower, isPlaying: audioManager.isPlaying)

                VStack {
                    Slider(value: Binding(get: {
                        audioManager.currentTime
                    }, set: { newValue in
                        audioManager.audioPlayer?.currentTime = newValue
                        audioManager.currentTime = newValue
                    }), in: 0...max(1, audioManager.duration))
                    .accentColor(.pink)
                    
                    HStack {
                        Text(audioManager.formatTime(audioManager.currentTime))
                        Spacer()
                        Text(audioManager.formatTime(audioManager.duration))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                }
                .padding(.horizontal, 10)

                HStack(spacing: 50) {
                    Button(action: audioManager.previousTrack) { Image(systemName: "backward.fill").font(.title) }
                    
                    Button(action: audioManager.playPause) {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 90))
                            .foregroundColor(.pink)
                            .shadow(color: .pink.opacity(0.4), radius: 15)
                    }
                    
                    Button(action: audioManager.nextTrack) { Image(systemName: "forward.fill").font(.title) }
                }
                .foregroundColor(.white)

                SystemVolumeSlider().frame(height: 30)

                Spacer()
            }
            .padding(.horizontal, 30)
        }
        .sheet(isPresented: $showInfo) {
            AuthorView()
        }
        .preferredColorScheme(.dark)
    }
}

struct AuthorView: View {
    var body: some View {
        VStack(spacing: 25) {
            Text("Antoni Dolatowski")
                .font(.system(size: 36, weight: .black))
                .padding(.top, 40)
            Text("Twórca tego potężnego playera.")
                .font(.headline)
                .foregroundColor(.gray)
            Divider().background(Color.pink)
            VStack(alignment: .leading, spacing: 20) {
                HStack { Image(systemName: "globe"); Text("atlashc.pl") }
                HStack { Image(systemName: "cpu"); Text("Stworzone na MacBook Air M2") }
                HStack { Image(systemName: "music.note"); Text("Playlista: ATHC Mix") }
            }
            .font(.title3)
            Spacer()
            Text("© 2024 Antoni - Nie kopiować, bo nasyłam morenkę.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(30)
    }
}