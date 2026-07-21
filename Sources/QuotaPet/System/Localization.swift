import Foundation

enum AppLanguage: String, CaseIterable, Equatable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static var current: AppLanguage {
        resolve(preferredLanguage: Locale.preferredLanguages.first)
    }

    static func resolve(preferredLanguage: String?) -> AppLanguage {
        guard let identifier = preferredLanguage?.lowercased() else { return .english }
        if identifier.hasPrefix("zh-hans") || identifier == "zh-cn" || identifier == "zh-sg" {
            return .simplifiedChinese
        }
        return .english
    }

    static func resolve(preference: LanguagePreference, preferredLanguage: String? = Locale.preferredLanguages.first) -> AppLanguage {
        switch preference {
        case .system: resolve(preferredLanguage: preferredLanguage)
        case .simplifiedChinese: .simplifiedChinese
        case .english: .english
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

enum LanguagePreference: String, CaseIterable, Codable, Equatable {
    case system
    case simplifiedChinese
    case english
}

enum L10n {
    enum Key: String, CaseIterable {
        case generalUsageLimit = "quota.general"
        case sparkUsageLimit = "quota.spark"
        case remainingUsedSummary = "usage.remaining_used"
        case usageUnavailable = "usage.unavailable"
        case confirmAndReadUsage = "usage.confirm_read"
        case resetAt = "usage.reset_at"
        case resetUnavailable = "usage.reset_unavailable"
        case resetCountdownUnavailable = "usage.countdown_unavailable"
        case usedPercent = "usage.used_percent"
        case remainingPercent = "usage.remaining_percent"
        case updatedAt = "usage.updated_at"
        case dataHealthy = "status.healthy"
        case readingUsage = "status.reading"
        case dataStale = "status.stale"
        case countdownDays = "countdown.days"
        case countdownHours = "countdown.hours"
        case countdownMinutes = "countdown.minutes"
        case durationDays = "duration.days"
        case durationHours = "duration.hours"
        case durationMinutes = "duration.minutes"
        case cycleSummary = "usage.cycle_summary"
        case meterAccessibility = "usage.meter_accessibility"
        case collapseDetails = "action.collapse_details"
        case codexUsage = "title.codex_usage"
        case willReadPath = "usage.will_read_path"
        case confirmLocalCodex = "usage.confirm_local_codex"
        case refreshNow = "action.refresh_now"
        case refreshing = "action.refreshing"
        case refreshSucceeded = "action.refresh_succeeded"
        case refreshTimeoutNotice = "action.refresh_timeout_notice"
        case refreshRecovering = "action.refresh_recovering"
        case ringUnavailable = "ring.unavailable"
        case ringRemaining = "ring.remaining"
        case ringRemainingReset = "ring.remaining_reset"
        case moodThriving = "mood.thriving"
        case moodContent = "mood.content"
        case moodConcerned = "mood.concerned"
        case moodCritical = "mood.critical"
        case moodSleeping = "mood.sleeping"
        case moodOffline = "mood.offline"
        case accessibilityRemaining = "accessibility.remaining"
        case accessibilityRemainingStale = "accessibility.remaining_stale"
        case accessibilityRemainingUnavailable = "accessibility.remaining_unavailable"
        case menuShowPet = "menu.show_pet"
        case menuRealtime = "menu.realtime"
        case menuEnergySaver = "menu.energy_saver"
        case menuRecoverInteraction = "menu.recover_interaction"
        case menuSettings = "menu.settings"
        case menuHelp = "menu.help"
        case menuAbout = "menu.about"
        case menuQuit = "menu.quit"
        case settingsTitle = "settings.title"
        case settingsSectionAppearance = "settings.section.appearance"
        case settingsSectionConnection = "settings.section.connection"
        case settingsSectionNotifications = "settings.section.notifications"
        case settingsSectionLanguage = "settings.section.language"
        case settingsShowPet = "settings.show_pet"
        case settingsShowPetHelp = "settings.show_pet.help"
        case settingsAlwaysOnTop = "settings.always_on_top"
        case settingsAlwaysOnTopHelp = "settings.always_on_top.help"
        case settingsMousePassthrough = "settings.mouse_passthrough"
        case settingsMousePassthroughHelp = "settings.mouse_passthrough.help"
        case settingsConnectionMode = "settings.connection_mode"
        case settingsRealtime = "settings.realtime"
        case settingsEnergySaver = "settings.energy_saver"
        case settingsModeHelp = "settings.mode_help"
        case settingsShortcut = "settings.shortcut"
        case settingsResetShortcut = "settings.reset_shortcut"
        case settingsNotifications = "settings.notifications"
        case settingsNotificationsHelp = "settings.notifications.help"
        case settingsLaunchAtLogin = "settings.launch_at_login"
        case settingsLaunchAtLoginHelp = "settings.launch_at_login.help"
        case settingsLanguage = "settings.language"
        case settingsLanguageSystem = "settings.language.system"
        case settingsLanguageChinese = "settings.language.chinese"
        case settingsLanguageEnglish = "settings.language.english"
        case settingsCodexTrust = "settings.codex_trust"
        case settingsCandidateDetails = "settings.candidate_details"
        case settingsNone = "settings.none"
        case settingsReviewTrust = "settings.review_trust"
        case settingsConfirmTrust = "settings.confirm_trust"
        case settingsTrusted = "settings.trusted"
        case settingsRejected = "settings.rejected"
        case settingsAboutLegal = "settings.about_legal"
        case settingsCurrentVersion = "settings.current_version"
        case settingsCheckForUpdates = "settings.check_for_updates"
        case settingsCheckingForUpdates = "settings.checking_for_updates"
        case settingsUpdateUpToDate = "settings.update.up_to_date"
        case settingsUpdateAvailable = "settings.update.available"
        case settingsUpdateNoRelease = "settings.update.no_release"
        case settingsUpdateFailed = "settings.update.failed"
        case settingsOpenDownloadPage = "settings.update.open_download"
        case settingsUnofficialNotice = "settings.unofficial_notice"
        case settingsMarksNotice = "settings.marks_notice"
        case aboutTitle = "about.title"
        case aboutVersion = "about.version"
        case aboutOK = "about.ok"
        case hotkeyOccupied = "hotkey.occupied"
        case hotkeyRegistrationFailed = "hotkey.registration_failed"
        case notificationTitle = "notification.title"
        case notificationExhausted = "notification.exhausted"
        case notificationThreshold = "notification.threshold"
        case errorNoUsageWindows = "error.no_usage_windows"
        case errorNoTrustedCodex = "error.no_trusted_codex"
        case errorTrustValidation = "error.trust_validation"
        case errorInvalidAppServerResponse = "error.invalid_app_server_response"
        case errorAppServerExited = "error.app_server_exited"
        case errorInvalidUsageResponse = "error.invalid_usage_response"
        case errorRequestTimedOut = "error.request_timed_out"
        case errorRequestFailed = "error.request_failed"
        case inspectionInvalidPath = "inspection.invalid_path"
        case inspectionRealpathFailed = "inspection.realpath_failed"
        case inspectionNotRegularFile = "inspection.not_regular_file"
        case inspectionNotExecutable = "inspection.not_executable"
        case inspectionWorldWritable = "inspection.world_writable"
        case inspectionGroupWritable = "inspection.group_writable"
        case inspectionUnsafeOwner = "inspection.unsafe_owner"
        case inspectionFileTooLarge = "inspection.file_too_large"
        case inspectionHashFailed = "inspection.hash_failed"
        case inspectionIdentityChanged = "inspection.identity_changed"
    }

    static func text(
        _ key: Key,
        language: AppLanguage = .current,
        arguments: [CVarArg] = []
    ) -> String {
        let bundle = localizedBundle(for: language) ?? localizedBundle(for: .english) ?? .main
        let format = bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        let resourceName = language == .simplifiedChinese ? "zh-hans" : language.rawValue
        guard let path = resourceBundle?.path(forResource: resourceName, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static let resourceBundle: Bundle? = {
        let bundleName = "QuotaPet_QuotaPet.bundle"
        let hostBundles = [Bundle.main, Bundle(for: LocalizationBundleToken.self)]
        for hostBundle in hostBundles {
            if let resourceURL = hostBundle.resourceURL {
                let candidate = resourceURL.appendingPathComponent(bundleName, isDirectory: true)
                if let bundle = Bundle(url: candidate) { return bundle }
            }
            guard var directory = hostBundle.executableURL?.deletingLastPathComponent() else { continue }
            for _ in 0..<5 {
                let candidate = directory.appendingPathComponent(bundleName, isDirectory: true)
                if let bundle = Bundle(url: candidate) { return bundle }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }()
}

private final class LocalizationBundleToken: NSObject {}

extension CodexExecutableInspectionError {
    func localizedMessage(language: AppLanguage = .current) -> String {
        let key: L10n.Key
        switch self {
        case .invalidPath: key = .inspectionInvalidPath
        case .realpathFailed: key = .inspectionRealpathFailed
        case .notRegularFile: key = .inspectionNotRegularFile
        case .notExecutable: key = .inspectionNotExecutable
        case .worldWritable: key = .inspectionWorldWritable
        case .groupWritable: key = .inspectionGroupWritable
        case .unsafeOwner: key = .inspectionUnsafeOwner
        case .fileTooLarge: key = .inspectionFileTooLarge
        case .hashFailed: key = .inspectionHashFailed
        case .identityChanged: key = .inspectionIdentityChanged
        }
        return L10n.text(key, language: language)
    }
}
