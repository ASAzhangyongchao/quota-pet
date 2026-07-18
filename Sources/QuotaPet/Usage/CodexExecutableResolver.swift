import CryptoKit
import Darwin
import Foundation
import Security

struct ExecutableCandidate: Equatable {
    enum Source: Equatable {
        case userSelected
        case chatGPTBundle
        case codexBundle
        case homeChatGPTBundle
        case homeCodexBundle
        case homebrew
        case local
        case path

        fileprivate var isBundle: Bool {
            switch self {
            case .chatGPTBundle, .codexBundle, .homeChatGPTBundle, .homeCodexBundle:
                true
            default:
                false
            }
        }
    }

    let canonicalURL: URL
    let source: Source
    let ownerUID: uid_t
    let mode: mode_t
    let signingIdentifier: String?
    let teamIdentifier: String?
    let codeHash: String
}

struct TrustFingerprint: Equatable, Hashable {
    let canonicalPath: String
    let codeHash: String
    let signingIdentifier: String?
    let teamIdentifier: String?
    let ownerUID: uid_t

    init(candidate: ExecutableCandidate) {
        canonicalPath = candidate.canonicalURL.path
        codeHash = candidate.codeHash
        signingIdentifier = candidate.signingIdentifier
        teamIdentifier = candidate.teamIdentifier
        ownerUID = candidate.ownerUID
    }
}

struct ExecutablePathInput: Equatable {
    let url: URL
    let source: ExecutableCandidate.Source
}

enum CodexExecutableInspectionError: Error, Equatable {
    case invalidPath
    case realpathFailed
    case notRegularFile
    case notExecutable
    case worldWritable
    case groupWritable
    case unsafeOwner
    case fileTooLarge
    case hashFailed
}

struct StaticExecutableInspection: Equatable {
    let candidate: ExecutableCandidate
    let signatureIsValid: Bool
    let bundleIdentifier: String?
}

protocol CodexExecutableInspecting {
    func inspect(url: URL, source: ExecutableCandidate.Source) throws -> StaticExecutableInspection
}

struct CodexStaticExecutableInspector: CodexExecutableInspecting {
    private static let maximumPathBytes = 4_096
    private static let maximumFileBytes = 512 * 1_024 * 1_024
    private static let hashChunkBytes = 64 * 1_024

    func inspect(url: URL, source: ExecutableCandidate.Source) throws -> StaticExecutableInspection {
        guard url.isFileURL, url.path.utf8.count <= Self.maximumPathBytes else {
            throw CodexExecutableInspectionError.invalidPath
        }
        var linkMetadata = stat()
        guard lstat(url.path, &linkMetadata) == 0 else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        let canonicalURL = try canonicalURL(for: url)
        var metadata = stat()
        guard stat(canonicalURL.path, &metadata) == 0 else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw CodexExecutableInspectionError.notRegularFile
        }
        guard (metadata.st_mode & 0o111) != 0 else {
            throw CodexExecutableInspectionError.notExecutable
        }
        guard (metadata.st_mode & S_IWOTH) == 0 else {
            throw CodexExecutableInspectionError.worldWritable
        }
        guard (metadata.st_mode & S_IWGRP) == 0 else {
            throw CodexExecutableInspectionError.groupWritable
        }
        guard metadata.st_uid == 0 || metadata.st_uid == getuid() else {
            throw CodexExecutableInspectionError.unsafeOwner
        }
        guard metadata.st_size >= 0, metadata.st_size <= off_t(Self.maximumFileBytes) else {
            throw CodexExecutableInspectionError.fileTooLarge
        }

        let signingURL = signingURL(for: canonicalURL)
        let signature = signingMetadata(for: signingURL)
        return StaticExecutableInspection(
            candidate: ExecutableCandidate(
                canonicalURL: canonicalURL,
                source: source,
                ownerUID: metadata.st_uid,
                mode: metadata.st_mode,
                signingIdentifier: signature.identifier,
                teamIdentifier: signature.teamIdentifier,
                codeHash: try hashFile(at: canonicalURL)
            ),
            signatureIsValid: signature.isValid,
            bundleIdentifier: signingURL.pathExtension == "app" ? Bundle(url: signingURL)?.bundleIdentifier : nil
        )
    }

    private func canonicalURL(for url: URL) throws -> URL {
        guard let resolvedPath = realpath(url.path, nil) else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        defer { free(resolvedPath) }
        return URL(fileURLWithPath: String(cString: resolvedPath))
    }

    private func hashFile(at url: URL) throws -> String {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var totalBytes = 0
            while let data = try handle.read(upToCount: Self.hashChunkBytes), !data.isEmpty {
                totalBytes += data.count
                guard totalBytes <= Self.maximumFileBytes else {
                    throw CodexExecutableInspectionError.fileTooLarge
                }
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch let error as CodexExecutableInspectionError {
            throw error
        } catch {
            throw CodexExecutableInspectionError.hashFailed
        }
    }

    private func signingMetadata(for url: URL) -> SigningMetadata {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return SigningMetadata()
        }

        let isValid = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [String: Any]
        else {
            return SigningMetadata(isValid: isValid)
        }
        return SigningMetadata(
            identifier: values[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String,
            isValid: isValid
        )
    }

    private func signingURL(for candidateURL: URL) -> URL {
        var currentURL = candidateURL.deletingLastPathComponent()
        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL
            }
            currentURL.deleteLastPathComponent()
        }
        return candidateURL
    }
}

private struct SigningMetadata {
    let identifier: String?
    let teamIdentifier: String?
    let isValid: Bool

    init(identifier: String? = nil, teamIdentifier: String? = nil, isValid: Bool = false) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.isValid = isValid
    }
}

enum ExecutableTrust: Equatable {
    case bundleAllowList
    case confirmed
    case requiresConfirmation
}

enum ExecutableResolution: Equatable {
    case accepted(ExecutableCandidate, trust: ExecutableTrust)
    case rejected(CodexExecutableInspectionError)

    var candidate: ExecutableCandidate? {
        guard case let .accepted(candidate, _) = self else { return nil }
        return candidate
    }

    var trust: ExecutableTrust? {
        guard case let .accepted(_, trust) = self else { return nil }
        return trust
    }

    var requiresConfirmation: Bool {
        trust == .requiresConfirmation
    }
}

final class CodexExecutableResolver {
    private static let maximumPathEntries = 64
    private static let maximumPathBytes = 32 * 1_024
    private static let maximumPathComponentBytes = 4_096
    private static let allowedSigningIdentifier = "com.openai.codex"
    private static let allowedTeamIdentifier = "2DC432GLL2"

    private let inspector: any CodexExecutableInspecting
    private var eligibleFingerprints: Set<TrustFingerprint> = []
    private var confirmedFingerprints: Set<TrustFingerprint> = []

    init(inspector: any CodexExecutableInspecting = CodexStaticExecutableInspector()) {
        self.inspector = inspector
    }

    static func candidateInputs(
        userSelectedURL: URL? = nil,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [ExecutablePathInput] {
        var inputs: [ExecutablePathInput] = []
        if let userSelectedURL {
            inputs.append(.init(url: userSelectedURL, source: .userSelected))
        }
        inputs.append(contentsOf: [
            .init(url: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"), source: .chatGPTBundle),
            .init(url: URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"), source: .codexBundle),
            .init(url: homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"), source: .homeChatGPTBundle),
            .init(url: homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"), source: .homeCodexBundle),
            .init(url: URL(fileURLWithPath: "/opt/homebrew/bin/codex"), source: .homebrew),
            .init(url: URL(fileURLWithPath: "/usr/local/bin/codex"), source: .local),
        ])
        guard let path, path.utf8.count <= Self.maximumPathBytes else {
            return inputs
        }
        inputs.append(contentsOf: path.split(separator: ":", omittingEmptySubsequences: true).prefix(Self.maximumPathEntries).compactMap { directory in
            guard directory.utf8.count <= Self.maximumPathComponentBytes else { return nil }
            return ExecutablePathInput(
                url: URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent("codex"),
                source: .path
            )
        })
        return inputs
    }

    func resolve(
        userSelectedURL: URL? = nil,
        path: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> [ExecutableResolution] {
        inspect(Self.candidateInputs(userSelectedURL: userSelectedURL, path: path))
    }

    func inspect(_ inputs: [ExecutablePathInput]) -> [ExecutableResolution] {
        var results: [ExecutableResolution] = []
        var canonicalPaths = Set<String>()
        for input in inputs.prefix(Self.maximumPathEntries + 7) {
            do {
                var inspection = try inspector.inspect(url: input.url, source: input.source)
                inspection = StaticExecutableInspection(
                    candidate: ExecutableCandidate(
                        canonicalURL: inspection.candidate.canonicalURL,
                        source: input.source,
                        ownerUID: inspection.candidate.ownerUID,
                        mode: inspection.candidate.mode,
                        signingIdentifier: inspection.candidate.signingIdentifier,
                        teamIdentifier: inspection.candidate.teamIdentifier,
                        codeHash: inspection.candidate.codeHash
                    ),
                    signatureIsValid: inspection.signatureIsValid,
                    bundleIdentifier: inspection.bundleIdentifier
                )
                guard canonicalPaths.insert(inspection.candidate.canonicalURL.path).inserted else { continue }
                let fingerprint = TrustFingerprint(candidate: inspection.candidate)
                eligibleFingerprints.insert(fingerprint)
                let trust = trust(for: inspection, fingerprint: fingerprint)
                results.append(.accepted(inspection.candidate, trust: trust))
            } catch let error as CodexExecutableInspectionError {
                results.append(.rejected(error))
            } catch {
                results.append(.rejected(.hashFailed))
            }
        }
        return results
    }

    func confirm(_ candidate: ExecutableCandidate) -> Bool {
        let fingerprint = TrustFingerprint(candidate: candidate)
        guard eligibleFingerprints.contains(fingerprint) else { return false }
        confirmedFingerprints.insert(fingerprint)
        return true
    }

    private func trust(for inspection: StaticExecutableInspection, fingerprint: TrustFingerprint) -> ExecutableTrust {
        if inspection.candidate.source.isBundle,
           inspection.signatureIsValid,
           inspection.bundleIdentifier == Self.allowedSigningIdentifier,
           inspection.candidate.signingIdentifier == Self.allowedSigningIdentifier,
           inspection.candidate.teamIdentifier == Self.allowedTeamIdentifier
        {
            return .bundleAllowList
        }
        return confirmedFingerprints.contains(fingerprint) ? .confirmed : .requiresConfirmation
    }
}
