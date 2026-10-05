import AVFoundation
import Observation
import SwiftUI

struct ReviewVideoCard<DragSurface: ViewModifier>: View {
    let player: AVPlayer
    let dragSurface: DragSurface
    let controlsEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = ReviewVideoPlayback()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                ReviewVideoSurface(player: player).allowsHitTesting(false)
                if let error = playback.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(24)
                } else if !playback.isReady {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .modifier(dragSurface)

            HStack(spacing: 8) {
                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(!playback.isReady)
                .accessibilityLabel(playback.isPlaying ? "Pause video" : "Play video")
                .accessibilityIdentifier("review.video.playPause")
                VStack(spacing: 0) {
                    Slider(value: Binding(get: { playback.position }, set: { playback.position = $0 }),
                           in: 0...max(playback.duration, 1), onEditingChanged: playback.setScrubbing)
                        .disabled(playback.duration <= 0 || !playback.isReady)
                        .accessibilityLabel("Video position")
                        .accessibilityValue(timeLabel(playback.position))
                        .accessibilityIdentifier("review.video.timeline")
                    HStack {
                        Text(timeLabel(playback.position))
                        Spacer()
                        Text(timeLabel(playback.duration))
                    }
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                Button(action: playback.toggleMute) {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(playback.isMuted ? "Unmute video" : "Mute video")
                .accessibilityIdentifier("review.video.mute")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .allowsHitTesting(controlsEnabled)
        }
        .onAppear { playback.attach(player) }
        .onChange(of: ObjectIdentifier(player)) { _, _ in playback.attach(player) }
        .onChange(of: controlsEnabled) { _, enabled in
            if !enabled { playback.pause() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.pause() }
        }
        .onDisappear { playback.detach() }
    }

    private func timeLabel(_ time: Double) -> String {
        let seconds = Int(max(0, time.isFinite ? time : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ReviewVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: VideoLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
    static func dismantleUIView(_ view: VideoLayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

private final class VideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor @Observable
private final class ReviewVideoPlayback {
    var position = 0.0
    private(set) var duration = 0.0
    private(set) var isPlaying = false
    private(set) var isMuted = false
    private(set) var isReady = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackObserver: NSKeyValueObservation?
    @ObservationIgnored private var readinessObserver: NSKeyValueObservation?
    private var generation = UUID()
    private var isScrubbing = false
    private var resumeAfterSeek = false

    func attach(_ player: AVPlayer) {
        if self.player === player { return }
        detach()
        self.player = player
        let token = generation
        playbackObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.updateSnapshot()
            }
        }
        readinessObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.updateSnapshot()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.updateSnapshot()
            }
        }
        updateSnapshot()
    }

    func detach() {
        generation = UUID()
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playbackObserver?.invalidate()
        readinessObserver?.invalidate()
        playbackObserver = nil
        readinessObserver = nil
        player = nil
        position = 0
        duration = 0
        isReady = false
        isPlaying = false
        errorMessage = nil
        isScrubbing = false
        resumeAfterSeek = false
    }

    func pause() {
        resumeAfterSeek = false
        player?.pause()
    }

    func togglePlayback() {
        guard let player, isReady else { return }
        if isPlaying { pause() }
        else {
            if duration > 0, position >= duration - 0.1 { player.seek(to: .zero) }
            player.play()
        }
        updateSnapshot()
    }

    func toggleMute() {
        guard let player else { return }
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    func setScrubbing(_ editing: Bool) {
        guard let player else { return }
        if editing {
            isScrubbing = true
            resumeAfterSeek = player.timeControlStatus != .paused
            player.pause()
        } else {
            let token = generation
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.isScrubbing = false
                    if finished && self.resumeAfterSeek && UIApplication.shared.applicationState == .active {
                        self.player?.play()
                    }
                    self.resumeAfterSeek = false
                    self.updateSnapshot()
                }
            }
        }
    }

    private func updateSnapshot() {
        guard let player else { return }
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        duration = itemDuration.isFinite ? max(0, itemDuration) : 0
        if !isScrubbing {
            let time = player.currentTime().seconds
            position = min(max(0, time.isFinite ? time : 0), max(duration, 1))
        }
        isPlaying = player.timeControlStatus != .paused
        isMuted = player.isMuted
        isReady = player.currentItem?.status == .readyToPlay
        errorMessage = player.currentItem?.status == .failed ? "This video could not be played." : nil
    }

    isolated deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        playbackObserver?.invalidate()
        readinessObserver?.invalidate()
    }
}
