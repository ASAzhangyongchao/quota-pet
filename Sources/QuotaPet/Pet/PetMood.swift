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
    case closed
}

public enum PetBrowShape: Equatable {
    case none
    case concerned
}

public enum PetMouthShape: Equatable {
    case smile
    case flat
    case frown
    case sleep
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
    public let mouthShape: PetMouthShape
    public let showsSweat: Bool
    public let showsSleepMark: Bool
    public let dashedRing: Bool
    public let palette: PetPalette
    public let staleOpacity: Double
    public let accessibilityLabel: String
    public let accessibilityValue: String

    init(snapshot: QuotaSnapshot) {
        switch snapshot.state {
        case .loading, .unavailable, .incompatible:
            self = Self.offline
        case .ready, .stale:
            guard let window = snapshot.primary else {
                self = Self.offline
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
                accessibilityValue: "剩余 \(Int(remaining.rounded()))%" + (isStale ? "，数据已过期" : "")
            )
        }
    }

    private init(
        mood: PetMood,
        usedFraction: Double?,
        dashedRing: Bool,
        staleOpacity: Double,
        accessibilityValue: String
    ) {
        self.mood = mood
        self.usedFraction = usedFraction
        self.dashedRing = dashedRing
        self.staleOpacity = staleOpacity
        self.accessibilityLabel = mood.accessibilityLabel
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
            eyeShape = .line
            browShape = .concerned
            mouthShape = .flat
            showsSweat = true
            showsSleepMark = false
            palette = .amber
        case .critical:
            eyeShape = .line
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

    private static let offline = PetRenderState(
        mood: .offline,
        usedFraction: nil,
        dashedRing: true,
        staleOpacity: 1,
        accessibilityValue: "剩余数据不可用"
    )

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}

extension PetRenderState {
    func blinking() -> PetRenderState {
        var copy = self
        copy.eyeShape = .closed
        return copy
    }
}

public enum PetAnimationEvent: Equatable {
    case stateChange
    case click
    case hover
    case idleBlink
}

public struct PetAnimationPolicy: Equatable {
    public let animationEnabled: Bool
    public let durationMilliseconds: Int?
    public let idleBlinkDelayRangeSeconds: ClosedRange<Int>?

    init(event: PetAnimationEvent, reduceMotion: Bool, petVisible: Bool, connectionMode: ConnectionMode) {
        guard !reduceMotion, petVisible, connectionMode != .energySaver else {
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
            durationMilliseconds = 140
            idleBlinkDelayRangeSeconds = 45...90
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

    mutating func consume(_ event: PetAnimationEvent, reduceMotion: Bool, petVisible: Bool, connectionMode: ConnectionMode) -> PetAnimationPolicy? {
        guard !isActive else { return nil }
        let policy = PetAnimationPolicy(event: event, reduceMotion: reduceMotion, petVisible: petVisible, connectionMode: connectionMode)
        guard policy.animationEnabled else { return nil }
        isActive = true
        return policy
    }

    mutating func complete() { isActive = false }
    mutating func cancel() { isActive = false }
}

private extension PetMood {
    var accessibilityLabel: String {
        switch self {
        case .thriving: "额度充足"
        case .content: "正常"
        case .concerned: "注意"
        case .critical: "即将耗尽"
        case .sleeping: "等待重置"
        case .offline: "离线"
        }
    }
}
