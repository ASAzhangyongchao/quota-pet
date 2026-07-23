import Foundation

public enum PetMood: Equatable {
    case thriving
    case content
    case concerned
    case critical
    case sleeping
    case offline

    public init(remainingPercent: Double) {
        switch min(max(remainingPercent, 0), 100) {
        case 60...100: self = .thriving
        case 30..<60: self = .content
        case 10..<30: self = .concerned
        case 1..<10: self = .critical
        default: self = .sleeping
        }
    }
}

public enum PetEyeShape: Equatable {
    case dot
    case line
    /// Slightly downturned lines — uneasy / critical resting face.
    case worried
    /// Half-closed mid-blink (anthropomorphic eyelid).
    case squint
    case closed
}

public enum PetBrowShape: Equatable {
    case none
    case concerned
}

public enum PetMouthShape: Equatable {
    case smile
    /// Brief wider smile during a happy blink.
    case softSmile
    case flat
    case frown
    case sleep
    /// Sleep “inhale” — mouth opens a touch without moving the body.
    case sleepOpen
}

public enum PetPalette: Equatable {
    case mint
    case clearBlue
    case amber
    case warningRed
    case grayRed
    case neutralGray
}

public struct PetRenderContract {
    public static let pathBudget = PetDrawingPlan.maximumPathCount
    public static let gradientBudget = PetDrawingPlan.maximumGradientCount
    public static let bodyMaxDimension = PetDrawingPlan.bodyMaxDimension
    public static let usesContinuousTimeline = false
    public static let externalAssetCount = 0
    public static let emojiGlyphCount = 0
}

public struct PetRenderState: Equatable {
    public let mood: PetMood
    public let usedFraction: Double?
    public var eyeShape: PetEyeShape
    public let browShape: PetBrowShape
    public var mouthShape: PetMouthShape
    public let showsSweat: Bool
    public let showsSleepMark: Bool
    public let dashedRing: Bool
    public let palette: PetPalette
    public let staleOpacity: Double
    public let remainingPercentText: String
    public let accessibilityLabel: String
    public let accessibilityValue: String

    init(snapshot: QuotaSnapshot, language: AppLanguage = .current) {
        switch snapshot.state {
        case .loading, .unavailable, .incompatible:
            self = Self.offline(language: language)
        case .ready, .stale:
            guard let window = snapshot.primary else {
                self = Self.offline(language: language)
                return
            }

            let remaining = Self.clamp(window.remainingPercent)
            let mood = PetMood(remainingPercent: remaining)
            let isStale: Bool
            if case .stale = snapshot.state {
                isStale = true
            } else {
                isStale = false
            }
            self.init(
                mood: mood,
                usedFraction: Self.clamp(window.usedPercent) / 100,
                dashedRing: false,
                staleOpacity: isStale ? 0.55 : 1,
                remainingPercentText: "\(Int(remaining.rounded()))%",
                accessibilityLabel: mood.accessibilityLabel(language: language),
                accessibilityValue: L10n.text(isStale ? .accessibilityRemainingStale : .accessibilityRemaining, language: language, arguments: [Int(remaining.rounded())])
            )
        }
    }

    private init(
        mood: PetMood,
        usedFraction: Double?,
        dashedRing: Bool,
        staleOpacity: Double,
        remainingPercentText: String,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.mood = mood
        self.usedFraction = usedFraction
        self.dashedRing = dashedRing
        self.staleOpacity = staleOpacity
        self.remainingPercentText = remainingPercentText
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue

        switch mood {
        case .thriving:
            eyeShape = .dot
            browShape = .none
            mouthShape = .smile
            showsSweat = false
            showsSleepMark = false
            palette = .mint
        case .content:
            eyeShape = .dot
            browShape = .none
            mouthShape = .smile
            showsSweat = false
            showsSleepMark = false
            palette = .clearBlue
        case .concerned:
            eyeShape = .worried
            browShape = .concerned
            mouthShape = .flat
            showsSweat = true
            showsSleepMark = false
            palette = .amber
        case .critical:
            eyeShape = .worried
            browShape = .concerned
            mouthShape = .frown
            showsSweat = true
            showsSleepMark = false
            palette = .warningRed
        case .sleeping:
            eyeShape = .closed
            browShape = .none
            mouthShape = .sleep
            showsSweat = false
            showsSleepMark = true
            palette = .grayRed
        case .offline:
            eyeShape = .line
            browShape = .none
            mouthShape = .flat
            showsSweat = false
            showsSleepMark = false
            palette = .neutralGray
        }
    }

    private static func offline(language: AppLanguage) -> PetRenderState {
        PetRenderState(
            mood: .offline,
            usedFraction: nil,
            dashedRing: true,
            staleOpacity: 1,
            remainingPercentText: "--",
            accessibilityLabel: PetMood.offline.accessibilityLabel(language: language),
            accessibilityValue: L10n.text(.accessibilityRemainingUnavailable, language: language)
        )
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}

/// Face-only idle pose. Never moves the whole pet body.
public enum PetIdleFacePose: Equatable {
    case squint
    case blink
    /// Closed eyes + slightly wider smile.
    case happyBlink
    /// Closed eyes + worried mouth twitch.
    case uneasyBlink
    /// Sleep mouth opens a little (breathing), eyes stay closed.
    case sleepInhale
}

extension PetRenderState {
    func blinking() -> PetRenderState {
        withIdleFace(.blink)
    }

    func withIdleFace(_ pose: PetIdleFacePose) -> PetRenderState {
        var copy = self
        switch pose {
        case .squint:
            if copy.eyeShape != .closed {
                copy.eyeShape = .squint
            }
        case .blink:
            copy.eyeShape = .closed
        case .happyBlink:
            copy.eyeShape = .closed
            if copy.mouthShape == .smile || copy.mouthShape == .softSmile {
                copy.mouthShape = .softSmile
            }
        case .uneasyBlink:
            copy.eyeShape = .closed
            if copy.mouthShape == .flat {
                copy.mouthShape = .frown
            }
        case .sleepInhale:
            copy.mouthShape = .sleepOpen
        }
        return copy
    }
}

public enum PetAnimationEvent: Equatable {
    case stateChange
    case click
    case hover
    case idleBlink
}

/// Mood-aware idle face sequence. Still one-shot; never a continuous timeline or body transform.
public enum PetIdleMotion: Equatable {
    /// Soft blink + smile accent — calm / happy.
    case happyFaceBlink
    /// Blink + uneasy mouth twitch — low quota.
    case uneasyFaceBlink
    /// Mouth-only sleep breath — already closed eyes.
    case sleepFaceBreath
    /// Simple blink — offline.
    case calmFaceBlink
}

public struct PetIdleFaceFrame: Equatable {
    public let atMilliseconds: Int
    public let pose: PetIdleFacePose
}

public extension PetMood {
    var idleMotion: PetIdleMotion {
        switch self {
        case .thriving, .content: .happyFaceBlink
        case .concerned, .critical: .uneasyFaceBlink
        case .sleeping: .sleepFaceBreath
        case .offline: .calmFaceBlink
        }
    }

    /// Keyframes for face redraws during one idle beat (body stays still).
    var idleFaceSequence: [PetIdleFaceFrame] {
        switch idleMotion {
        case .happyFaceBlink:
            [
                PetIdleFaceFrame(atMilliseconds: 0, pose: .squint),
                PetIdleFaceFrame(atMilliseconds: 55, pose: .happyBlink),
                PetIdleFaceFrame(atMilliseconds: 170, pose: .squint),
            ]
        case .uneasyFaceBlink:
            [
                PetIdleFaceFrame(atMilliseconds: 0, pose: .squint),
                PetIdleFaceFrame(atMilliseconds: 70, pose: .uneasyBlink),
                PetIdleFaceFrame(atMilliseconds: 200, pose: .squint),
            ]
        case .sleepFaceBreath:
            [PetIdleFaceFrame(atMilliseconds: 0, pose: .sleepInhale)]
        case .calmFaceBlink:
            [
                PetIdleFaceFrame(atMilliseconds: 0, pose: .squint),
                PetIdleFaceFrame(atMilliseconds: 60, pose: .blink),
                PetIdleFaceFrame(atMilliseconds: 160, pose: .squint),
            ]
        }
    }
}

public struct PetAnimationPolicy: Equatable {
    public let animationEnabled: Bool
    public let durationMilliseconds: Int?
    public let idleBlinkDelayRangeSeconds: ClosedRange<Int>?

    init(event: PetAnimationEvent, reduceMotion: Bool, petVisible: Bool, connectionMode: ConnectionMode, mood: PetMood = .content) {
        // Energy-saver only gates the Codex App Server process, not cheap one-shot pet motions.
        _ = connectionMode
        guard !reduceMotion, petVisible else {
            animationEnabled = false
            durationMilliseconds = nil
            idleBlinkDelayRangeSeconds = nil
            return
        }

        animationEnabled = true
        switch event {
        case .stateChange:
            durationMilliseconds = 220
            idleBlinkDelayRangeSeconds = nil
        case .click:
            durationMilliseconds = 200
            idleBlinkDelayRangeSeconds = nil
        case .hover:
            durationMilliseconds = 180
            idleBlinkDelayRangeSeconds = nil
        case .idleBlink:
            // Face keyframes need a beat long enough to read as a blink, not a flash.
            durationMilliseconds = mood == .sleeping ? 320 : 280
            idleBlinkDelayRangeSeconds = 8...16
        }
    }

    public func nextIdleBlinkDelay(randomUnit: Double) -> Int? {
        guard let range = idleBlinkDelayRangeSeconds else { return nil }
        let unit = min(max(randomUnit, 0), 1)
        let offset = Int((Double(range.upperBound - range.lowerBound) * unit).rounded())
        return range.lowerBound + offset
    }
}

struct PetAnimationGate {
    private(set) var isActive = false

    mutating func consume(
        _ event: PetAnimationEvent,
        reduceMotion: Bool,
        petVisible: Bool,
        connectionMode: ConnectionMode,
        mood: PetMood = .content
    ) -> PetAnimationPolicy? {
        guard !isActive else { return nil }
        let policy = PetAnimationPolicy(
            event: event,
            reduceMotion: reduceMotion,
            petVisible: petVisible,
            connectionMode: connectionMode,
            mood: mood
        )
        guard policy.animationEnabled else { return nil }
        isActive = true
        return policy
    }

    mutating func complete() { isActive = false }
    mutating func cancel() { isActive = false }
}

private extension PetMood {
    func accessibilityLabel(language: AppLanguage) -> String {
        switch self {
        case .thriving: L10n.text(.moodThriving, language: language)
        case .content: L10n.text(.moodContent, language: language)
        case .concerned: L10n.text(.moodConcerned, language: language)
        case .critical: L10n.text(.moodCritical, language: language)
        case .sleeping: L10n.text(.moodSleeping, language: language)
        case .offline: L10n.text(.moodOffline, language: language)
        }
    }
}
