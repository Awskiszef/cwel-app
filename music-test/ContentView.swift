import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import CoreMotion

// MARK: - Manager Ruchu (Parallax)
class MotionManager: ObservableObject {
    // To jest ta część, która sprawia, że okładka pływa.
    // Jakby była pijana. Ale tak artystycznie.
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    private let manager = CMMotionManager()

    init() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let self, let motion else { return }
                self.pitch = motion.attitude.pitch
                self.roll = motion.attitude.roll
            }
        }
    }
}

// MARK: - Systemowy Suwak Głośności
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

// MARK: - Wizualizator Dźwięku (Zoptymalizowany)
struct AudioVisualizer: View {
    var power: Float
    var isPlaying: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<15) { _ in
                let heightMultiplier = CGFloat.random(in: 0.6...1.0)
                let barHeight = isPlaying ? max(2, CGFloat(power) * 60 * heightMultiplier) : 2
                
                Capsule()
                    .frame(width: 4, height: barHeight)
                    .foregroundColor(.pink)
            }
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.08), value: power)
    }
}

// MARK: - Manager Audio (Zoptymalizowany)
class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    struct Track: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let artist: String
        let fileName: String
    }
    
    enum RepeatMode {
        case none, one, all
    }

    private var originalPlaylist: [Track] = []
    @Published var playlist: [Track] = []
    @Published var currentIndex: Int = 0
    var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isShuffling = false
    @Published var repeatMode: RepeatMode = .none
    @Published var audioPower: Float = 0.0

    var currentTrack: Track? {
        guard playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    private var timer: AnyCancellable?

    override init() {
        super.init()
        let initialTracks = [
            Track(title: "taobao", artist: "yungmioder, mlodygolab", fileName: "taobao"),
            Track(title: "morenka", artist: "yungmioder, mlodygolab, ava7ktp, got", fileName: "morenka"),
            Track(title: "shortnuke", artist: "yungmioder, mlodygolab, olliethawave", fileName: "shortnuke"),
            Track(title: "riot games", artist: "yungmioder, mlodygolab", fileName: "riot_games"),
            Track(title: "glowa", artist: "yungmioder, mlodygolab, plnjosh", fileName: "glowa"),
            Track(title: "niepokonani", artist: "yungmioder, mlodygolab, plnjosh, gbpjohnn", fileName: "niepokonani"),
            Track(title: "hvh", artist: "yungmioder, mlodygolab", fileName: "hvh")
        ]
        self.originalPlaylist = initialTracks
        self.playlist = initialTracks
        setupRemoteCommands()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        
        switch repeatMode {
        case .none:
            if isShuffling || currentIndex < playlist.count - 1 {
                nextTrack()
            } else {
                stop()
            }
        case .one:
            playTrack(at: currentIndex)
        case .all:
            nextTrack()
        }
    }

    func playPause() {
        guard let player = audioPlayer else {
            startNewPlayer()
            return
        }
        
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.cancel()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlaying()
    }

    func startNewPlayer() {
        guard let track = currentTrack else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
        }

        guard let path = Bundle.main.path(forResource: track.fileName, ofType: "mp3") else {
            print("Error: Audio file not found for \(track.fileName).mp3")
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
            print("Error loading audio player: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                
                player.updateMeters()
                let power = player.averagePower(forChannel: 0)
                let normalizedPower = self.normalizePower(power)
                self.audioPower = normalizedPower
            }
    }
    
    private func normalizePower(_ power: Float) -> Float {
        guard power.isFinite else { return 0.0 }
        let minDb: Float = -80.0
        if power < minDb { return 0.0 }
        if power >= 0.0 { return 1.0 }
        let root: Float = 2.0
        return pow((power - minDb) / -minDb, 1.0 / root)
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        updateNowPlaying()
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        audioPower = 0
        timer?.cancel()
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
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? "Unknown"
        info[MPMediaItemPropertyArtist] = currentTrack?.artist ?? "Unknown"
        
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

    func playTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        audioPlayer?.stop()
        startNewPlayer()
    }

    func nextTrack() {
        if isShuffling {
            let nextIndex = Int.random(in: 0..<playlist.count)
            playTrack(at: nextIndex)
        } else {
            let nextIndex = (currentIndex + 1) % playlist.count
            playTrack(at: nextIndex)
        }
    }

    func previousTrack() {
        if isShuffling {
            nextTrack()
        } else {
            let prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
            playTrack(at: prevIndex)
        }
    }
    
    func toggleShuffle() {
        isShuffling.toggle()
        guard let current = currentTrack else { return }
        
        if isShuffling {
            var newPlaylist = originalPlaylist.shuffled()
            if let index = newPlaylist.firstIndex(of: current) {
                newPlaylist.swapAt(0, index)
            }
            playlist = newPlaylist
            currentIndex = 0
        } else {
            playlist = originalPlaylist
            currentIndex = playlist.firstIndex(of: current) ?? 0
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .none: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .none
        }
    }
}

// MARK: - Widok Główny (Przebudowany)
struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var motionManager = MotionManager()
    @State private var showInfo = false
    @State private var isSeeking = false

    private var repeatIcon: String {
        switch audioManager.repeatMode {
        case .none: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    var body: some View {
        ZStack {
            Image("okladka")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .blur(radius: 40)
                .opacity(0.5)
            
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 15) {
                headerView
                Spacer(minLength: 10)
                coverArtView
                trackInfoView
                AudioVisualizer(power: audioManager.audioPower, isPlaying: audioManager.isPlaying)
                progressBarView.padding(.vertical, 10)
                mainControlsView
                volumeAndSecondaryControlsView.padding(.top, 10)
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 35)
        }
        .sheet(isPresented: $showInfo) {
            AuthorView()
        }
        .preferredColorScheme(.dark)
    }

    private var headerView: some View {
        HStack {
            Button(action: {}) { Image(systemName: "square.and.arrow.up") }
            Spacer()
            Text("ATHC PLAYER").font(.system(size: 14, weight: .bold)).tracking(2).foregroundColor(.pink)
            Spacer()
            Button(action: { showInfo = true }) { Image(systemName: "info.circle.fill") }
        }
        .foregroundColor(.white)
    }
    
    private var coverArtView: some View {
        Image("okladka")
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(20)
            .shadow(color: .pink.opacity(0.4), radius: 20)
            .offset(x: CGFloat(motionManager.roll * 20), y: CGFloat(motionManager.pitch * 20))
            .rotation3DEffect(.degrees(motionManager.roll * 10), axis: (x: 0, y: 1, z: 0))
    }
    
    private var trackInfoView: some View {
        VStack(spacing: 5) {
            Text(audioManager.currentTrack?.title ?? "Wybierz utwór")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Text(audioManager.currentTrack?.artist ?? "")
                .font(.title3.weight(.light))
                .foregroundColor(.gray)
        }
    }
    
    private var progressBarView: some View {
        VStack {
            Slider(value: Binding(get: {
                audioManager.currentTime
            }, set: { newValue in
                audioManager.seek(to: newValue)
                audioManager.currentTime = newValue
            }), in: 0...max(1, audioManager.duration))
            .accentColor(.pink)
            
            HStack {
                Text(audioManager.formatTime(audioManager.currentTime))
                Spacer()
                Text(audioManager.formatTime(audioManager.duration))
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
    }
    
    private var mainControlsView: some View {
        HStack(spacing: 40) {
            Button(action: audioManager.previousTrack) { Image(systemName: "backward.fill").font(.largeTitle) }
            Button(action: audioManager.playPause) {
                Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.pink)
            }
            Button(action: audioManager.nextTrack) { Image(systemName: "forward.fill").font(.largeTitle) }
        }
        .foregroundColor(.white)
    }
    
    private var volumeAndSecondaryControlsView: some View {
        VStack(spacing: 20) {
            SystemVolumeSlider().frame(height: 25)
            
            HStack {
                Button(action: audioManager.toggleShuffle) {
                    Image(systemName: "shuffle")
                        .foregroundColor(audioManager.isShuffling ? .pink : .white)
                }
                Spacer()
                Button(action: audioManager.cycleRepeatMode) {
                    Image(systemName: repeatIcon)
                        .foregroundColor(audioManager.repeatMode != .none ? .pink : .white)
                }
            }
            .font(.title2)
        }
    }
}

struct AuthorView: View {
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 5) {
                Text("Antoni Dolatowski")
                    .font(.largeTitle.weight(.bold))
                Text("iOS Developer")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 20) {
                Link("Portfolio: atlashc.pl", destination: URL(string: "https://atlashc.pl")!)
                Link("GitHub: Awskiszef", destination: URL(string: "https://github.com/Awskiszef")!)
                Link("LinkedIn: /in/awski", destination: URL(string: "https://linkedin.com/in/awski")!)
            }
            .font(.headline)
            .accentColor(.pink)
            
            Spacer()
        }
        .padding(30)
    }
}
