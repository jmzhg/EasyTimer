import SwiftUI
import Foundation
import Combine
import AVFoundation
import AudioToolbox

enum TimerState {
    case idle
    case running(currentIndex: Int, round: Int, remaining: TimeInterval)
    case paused(currentIndex: Int, round: Int, remaining: TimeInterval)
    case finished
}

@MainActor
final class WorkoutTimer: ObservableObject {
    @Published private(set) var state: TimerState = .idle

    private var task: Task<Void, Never>?
    private var currentIndex = 0
    private var currentRound = 1

    // Cached pause state (guards against race conditions when cancelling the task)
    private var pausedIndex: Int?
    private var pausedRound: Int?
    private var pausedRemaining: TimeInterval?

    // MARK: - Haptics & Sound
    private let successHaptics = UINotificationFeedbackGenerator()
    private let heavyHaptics = UIImpactFeedbackGenerator(style: .heavy)
    private var audioPlayer: AVAudioPlayer?

    // User preference keys (kept in sync with RunnerView's @AppStorage)
    private let enableHapticsKey = "enableHaptics"
    private let enableSoundsKey  = "enableSounds"
    private let soundIDKey       = "soundID"
    private let restSoundIDKey   = "restSoundID"

    private var enableHapticsPref: Bool {
        if UserDefaults.standard.object(forKey: enableHapticsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enableHapticsKey)
    }
    private var enableSoundsPref: Bool {
        if UserDefaults.standard.object(forKey: enableSoundsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enableSoundsKey)
    }
    private var selectedSoundID: Int {
        let val = UserDefaults.standard.integer(forKey: soundIDKey)
        return val == 0 ? 0 : val // 0 = use bundled bell if available
    }
    private var selectedRestSoundID: Int {
        let val = UserDefaults.standard.integer(forKey: restSoundIDKey)
        return val == 0 ? 0 : val // 0 = use bundled sound if available
    }

    func start(workout: Workout) {
        prepareFeedback()
        stop()
        currentIndex = 0
        currentRound = 1
        run(workout: workout, resumeRemaining: nil)
    }

    func pause() {
        switch state {
        case .running(let idx, let round, let remaining):
            // Cache values in case the async task laps for one more tick after we set state
            pausedIndex = idx
            pausedRound = round
            pausedRemaining = remaining
            state = .paused(currentIndex: idx, round: round, remaining: remaining)
            task?.cancel()
        default:
            break
        }
    }

    func resume(workout: Workout) {
        prepareFeedback()

        var idx: Int?
        var round: Int?
        var remaining: TimeInterval?

        if case .paused(let i, let r, let rem) = state {
            idx = i; round = r; remaining = rem
        } else {
            // Fallback to cached pause values if state was mutated by the async task timing
            idx = pausedIndex; round = pausedRound; remaining = pausedRemaining
        }

        guard let i = idx, let r = round, let rem = remaining else { return }

        currentIndex = i
        currentRound = r
        // Optimistically update UI to show we're resuming
        state = .running(currentIndex: i, round: r, remaining: rem)

        run(workout: workout, resumeRemaining: rem)
    }

    func skipToNextSegment(workout: Workout) {
        // Allow from running or paused states
        switch state {
        case .running(let idx, let round, _), .paused(let idx, let round, _):
            currentIndex = idx
            currentRound = round
            // Cancel current task and immediately advance index
            task?.cancel()
            let segments = workout.segments.sorted { $0.order < $1.order }
            if currentIndex < segments.count - 1 {
                currentIndex += 1
            } else {
                // end of segment list -> advance round
                currentIndex = 0
                if currentRound < workout.totalRounds { currentRound += 1 } else { state = .finished; return }
            }
            // Restart with full duration of the new segment
            run(workout: workout, resumeRemaining: nil)
        default:
            return
        }
    }

    func skipToNextSet(workout: Workout) {
        // A "set" here means jumping to the first segment of the next round
        switch state {
        case .running(_, let round, _), .paused(_, let round, _):
            task?.cancel()
            _ = workout.segments.sorted { $0.order < $1.order }
            if round < workout.totalRounds {
                currentRound = round + 1
                currentIndex = 0
                run(workout: workout, resumeRemaining: nil)
            } else {
                // Already in final round -> finish
                state = .finished
            }
        default:
            return
        }
    }

    func skipToPreviousSegment(workout: Workout) {
        switch state {
        case .running(let idx, let round, _), .paused(let idx, let round, _):
            currentIndex = idx
            currentRound = round
            task?.cancel()
            let segments = workout.segments.sorted { $0.order < $1.order }
            if currentIndex > 0 {
                currentIndex -= 1
            } else if currentRound > 1 {
                currentRound -= 1
                currentIndex = max(0, segments.count - 1)
            } else {
                currentIndex = 0
            }
            run(workout: workout, resumeRemaining: nil)
        default:
            return
        }
    }

    func skipToPreviousSet(workout: Workout) {
        switch state {
        case .running(_, let round, _), .paused(_, let round, _):
            task?.cancel()
            if round > 1 {
                currentRound = round - 1
                currentIndex = 0
                run(workout: workout, resumeRemaining: nil)
            } else {
                // already first round; restart first segment
                currentRound = 1
                currentIndex = 0
                run(workout: workout, resumeRemaining: nil)
            }
        default:
            return
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .idle
        pausedIndex = nil
        pausedRound = nil
        pausedRemaining = nil
    }

    private func run(workout: Workout, resumeRemaining: TimeInterval?) {
        let segments = workout.segments.sorted { $0.order < $1.order }
        task = Task { [weak self] in
            guard let self else { return }
            pausedIndex = nil
            pausedRound = nil
            pausedRemaining = nil
            var remainingForCurrent = resumeRemaining

            outerLoop: while currentRound <= workout.totalRounds {
                while currentIndex < segments.count {
                    let segment = segments[currentIndex]
                    let duration = remainingForCurrent ?? segment.duration
                    remainingForCurrent = nil

                    var remaining = duration
                    let tick: TimeInterval = 0.1

                    while remaining > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                        // If pause/stop cancelled the task, exit immediately before touching state
                        if Task.isCancelled { return }
                        remaining = max(0, remaining - tick)
                        await MainActor.run {
                            self.state = .running(currentIndex: self.currentIndex, round: self.currentRound, remaining: remaining)
                        }
                    }

                    // Segment completed — determine what's next to pick the correct tone
                    let isLastInRound = (currentIndex == segments.count - 1)
                    let nextIsRest: Bool = {
                        if isLastInRound {
                            // If another round remains, the next segment will be the first segment again
                            if self.currentRound < workout.totalRounds, let first = segments.first { return first.kind == .rest }
                            return false // session end; handled below
                        } else {
                            return segments[self.currentIndex + 1].kind == .rest
                        }
                    }()
                    notifyTransition(nextIsRest: nextIsRest)

                    currentIndex += 1
                }

                currentIndex = 0
                currentRound += 1
            }

            // Entire session finished — success feedback
            notifyTransition(nextIsRest: false, isSessionEnd: true)

            await MainActor.run {
                self.state = .finished
                self.task = nil
            }
        }
    }

    // MARK: - Feedback Helpers
    private func prepareFeedback() {
        if enableHapticsPref {
            successHaptics.prepare()
            heavyHaptics.prepare()
        }
        guard enableSoundsPref else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            #if DEBUG
            print("[AudioSession] Failed to activate: \(error)")
            #endif
        }
    }

    private func playBell(isRest: Bool = false) {
        let selection = isRest ? selectedRestSoundID : selectedSoundID
        let resolved = SoundResolver.resolve(selection: selection, isRest: isRest)
        if let url = resolved.url {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                return
            } catch {
                #if DEBUG
                print("[Audio] Failed to play bundled sound: \(error)")
                #endif
            }
        }
        AudioServicesPlaySystemSound(resolved.systemID)
    }

    private func notifyTransition(nextIsRest: Bool = false, isSessionEnd: Bool = false) {
        if enableHapticsPref {
            if isSessionEnd {
                successHaptics.notificationOccurred(.success)
            } else {
                heavyHaptics.impactOccurred()
            }
        }
        if enableSoundsPref {
            playBell(isRest: nextIsRest && !isSessionEnd)
        }
    }
}

struct RunnerView: View {
    let workout: Workout
    @StateObject private var timer = WorkoutTimer()
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingSettings = false
    @AppStorage("enableHaptics") private var enableHaptics = true
    @AppStorage("enableSounds")  private var enableSounds  = true
    // 0 = use bundled bell if present; otherwise fallback to 1007 (Tock)
    @AppStorage("soundID")       private var soundID: Int  = 0
    @AppStorage("restSoundID")   private var restSoundID: Int = 0

    var body: some View {
        VStack(spacing: 24) {
            Text(workout.name).font(.largeTitle).bold()

            switch timer.state {
            case .idle:
                Text("Ready")
            case .running(let idx, let round, let remaining),
                 .paused(let idx, let round, let remaining):
                let segment = workout.segments.sorted { $0.order < $1.order }[idx]
                Text(segment.title ?? segment.kind.rawValue.capitalized)
                    .font(.title)
                Text(timeString(remaining))
                    .monospacedDigit()
                    .font(.system(size: 64, weight: .bold))
                Text("Round \(round) / \(workout.totalRounds)")
                    .foregroundStyle(.secondary)
            case .finished:
                Text("Done!").font(.title)
            }

            HStack(spacing: 20) {
                // Previous Set
                Button {
                    timer.skipToPreviousSet(workout: workout)
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .disabled({ if case .running = timer.state { return false }; if case .paused = timer.state { return false }; return true }())

                // Previous Rep
                Button {
                    timer.skipToPreviousSegment(workout: workout)
                } label: {
                    Image(systemName: "backward.circle.fill")
                }
                .disabled({ if case .running = timer.state { return false }; if case .paused = timer.state { return false }; return true }())

                // Play/Pause toggle
                Button {
                    switch timer.state {
                    case .idle:
                        timer.start(workout: workout)
                    case .running:
                        timer.pause()
                    case .paused:
                        timer.resume(workout: workout)
                    case .finished:
                        timer.start(workout: workout)
                    }
                } label: {
                    Image(systemName: {
                        switch timer.state {
                        case .running: return "pause.fill"
                        case .paused, .idle, .finished: return "play.fill"
                        }
                    }())
                }

                // Next Rep
                Button {
                    timer.skipToNextSegment(workout: workout)
                } label: {
                    Image(systemName: "forward.circle.fill")
                }
                .disabled({ if case .running = timer.state { return false }; if case .paused = timer.state { return false }; return true }())

                // Next Set
                Button {
                    timer.skipToNextSet(workout: workout)
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled({ if case .running = timer.state { return false }; if case .paused = timer.state { return false }; return true }())
            }
            .font(.system(size: 28, weight: .semibold))
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                Form {
                    Section("Feedback") {
                        Toggle("Haptics", isOn: $enableHaptics)
                        Toggle("Sounds", isOn: $enableSounds)
                    }
                    Section("Sound") {
                        Picker("Tone", selection: $soundID) {
                            // 0 = bundled bell if available; fall back to system sound
                            Text("Bundled Bell (Default)").tag(0)
                            // Suggested "Ding"-like tones
                            Text("Ding (1013)").tag(1013)
                            Text("Chime (1105)").tag(1105)
                            Text("Tock (1007)").tag(1007)
                        }
                        Picker("Rest Tone", selection: $restSoundID) {
                            Text("Bundled Rest (Default)").tag(0)
                            // Softer options for rest
                            Text("Soft Ding (1105)").tag(1105)
                            Text("Tock (1007)").tag(1007)
                            Text("Ding (1013)").tag(1013)
                        }
                    }
                    Section(footer: Text("Tip: Add a short bell.caf (<1s) to the app bundle for the best experience.")) {
                        EmptyView()
                    }
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { isShowingSettings = false } }
                }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    let w = Workout(name: "Sample", totalRounds: 2)
    w.segments = [
        Segment(order: 0, kind: .work, duration: 3, title: "Work"),
        Segment(order: 1, kind: .rest, duration: 2, title: "Rest")
    ]
    return RunnerView(workout: w)
}
