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

    }

    let canonicalURL: URL
    let source: Source
    let ownerUID: uid_t
    let mode: mode_t
    let signingIdentifier: String?
    let teamIdentifier: String?
    let codeHash: String
    let deviceID: dev_t
    let inode: ino_t
    let inputURL: URL
}

struct TrustFingerprint: Codable, Equatable, Hashable {
    let canonicalPath: String
    let codeHash: String
    let signingIdentifier: String?
    let teamIdentifier: String?
    let ownerUID: uid_t
    let deviceID: dev_t
    let inode: ino_t

    init(candidate: ExecutableCandidate) {
        canonicalPath = candidate.canonicalURL.path
        codeHash = candidate.codeHash
        signingIdentifier = candidate.signingIdentifier
        teamIdentifier = candidate.teamIdentifier
        ownerUID = candidate.ownerUID
        deviceID = candidate.deviceID
        inode = candidate.inode
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
    case identityChanged
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
    private let signingInspector: any CodeSigningInspecting

    init(signingInspector: any CodeSigningInspecting = SecurityCodeSigningInspector()) {
        self.signingInspector = signingInspector
    }

    func inspect(url: URL, source: ExecutableCandidate.Source) throws -> StaticExecutableInspection {
        guard url.isFileURL, url.path.utf8.count <= Self.maximumPathBytes else {
            throw CodexExecutableInspectionError.invalidPath
        }
        var linkMetadata = stat()
        guard lstat(url.path, &linkMetadata) == 0 else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        let canonicalURL = try canonicalURL(for: url)
        let descriptor = open(canonicalURL.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let metadata = try fileMetadata(for: descriptor)
        try validate(metadata)
        let signingURL = signingURL(for: canonicalURL)
        let signature = signingInspector.metadata(for: signingURL)
        let codeHash: String
        if signature.isValid, let codeDirectoryHash = signature.codeDirectoryHash, !codeDirectoryHash.isEmpty {
            codeHash = codeDirectoryHash.hexadecimalString
        } else {
            codeHash = try hashFile(from: handle)
        }
        guard sameIdentity(metadata, try fileMetadata(for: descriptor)),
              sameIdentity(metadata, try pathMetadata(for: canonicalURL))
        else {
            throw CodexExecutableInspectionError.identityChanged
        }
        return StaticExecutableInspection(
            candidate: ExecutableCandidate(
                canonicalURL: canonicalURL,
                source: source,
                ownerUID: metadata.st_uid,
                mode: metadata.st_mode,
                signingIdentifier: signature.identifier,
                teamIdentifier: signature.teamIdentifier,
                codeHash: codeHash,
                deviceID: metadata.st_dev,
                inode: metadata.st_ino,
                inputURL: url
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

    private func validate(_ metadata: stat) throws {
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
    }

    private func fileMetadata(for descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw CodexExecutableInspectionError.identityChanged
        }
        return metadata
    }

    private func pathMetadata(for url: URL) throws -> stat {
        var metadata = stat()
        guard stat(url.path, &metadata) == 0 else {
            throw CodexExecutableInspectionError.identityChanged
        }
        return metadata
    }

    private func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev &&
            lhs.st_ino == rhs.st_ino &&
            lhs.st_size == rhs.st_size &&
            lhs.st_mode == rhs.st_mode &&
            lhs.st_uid == rhs.st_uid
    }

    private func hashFile(from handle: FileHandle) throws -> String {
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Self.hashChunkBytes,
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer { buffer.deallocate() }
        var hasher = SHA256()
        var totalBytes = 0
        while true {
            let bytesRead = Darwin.read(handle.fileDescriptor, buffer, Self.hashChunkBytes)
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw CodexExecutableInspectionError.hashFailed
            }
            guard bytesRead > 0 else { break }
            totalBytes += bytesRead
            guard totalBytes <= Self.maximumFileBytes else {
                throw CodexExecutableInspectionError.fileTooLarge
            }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

protocol CodeSigningInspecting {
    func metadata(for url: URL) -> SigningMetadata
}

struct SecurityCodeSigningInspector: CodeSigningInspecting {
    func metadata(for url: URL) -> SigningMetadata {
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
            codeDirectoryHash: values[kSecCodeInfoUnique as String] as? Data,
            isValid: isValid
        )
    }
}

struct SigningMetadata {
    let identifier: String?
    let teamIdentifier: String?
    let codeDirectoryHash: Data?
    let isValid: Bool

    init(
        identifier: String? = nil,
        teamIdentifier: String? = nil,
        codeDirectoryHash: Data? = nil,
        isValid: Bool = false
    ) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.codeDirectoryHash = codeDirectoryHash
        self.isValid = isValid
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
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
    private static let chatGPTSystemPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
    private static let codexSystemPath = "/Applications/Codex.app/Contents/Resources/codex"

    private let inspector: any CodexExecutableInspecting
    private var eligibleFingerprints: Set<TrustFingerprint> = []
    private var confirmedFingerprints: Set<TrustFingerprint> = []
    private let onConfirmedFingerprintsChanged: ((Set<TrustFingerprint>) -> Void)?

    init(
        inspector: any CodexExecutableInspecting = CodexStaticExecutableInspector(),
        confirmedFingerprints: Set<TrustFingerprint> = [],
        onConfirmedFingerprintsChanged: ((Set<TrustFingerprint>) -> Void)? = nil
    ) {
        self.inspector = inspector
        self.confirmedFingerprints = confirmedFingerprints
        self.onConfirmedFingerprintsChanged = onConfirmedFingerprintsChanged
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
                let inspection = normalize(try inspector.inspect(url: input.url, source: input.source), input: input)
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
        let input = ExecutablePathInput(url: candidate.inputURL, source: candidate.source)
        do {
            let inspection = normalize(try inspector.inspect(url: input.url, source: input.source), input: input)
            // Prefer the freshly inspected identity so ChatGPT updates still confirm.
            let fingerprint = TrustFingerprint(candidate: inspection.candidate)
            eligibleFingerprints.insert(fingerprint)
            confirmedFingerprints.insert(fingerprint)
            return true
        } catch {
            let fingerprint = TrustFingerprint(candidate: candidate)
            guard eligibleFingerprints.contains(fingerprint) else { return false }
            confirmedFingerprints.insert(fingerprint)
            return true
        }
    }

    func revalidate(_ candidate: ExecutableCandidate) -> Bool {
        let input = ExecutablePathInput(url: candidate.inputURL, source: candidate.source)
        do {
            let inspection = normalize(try inspector.inspect(url: input.url, source: input.source), input: input)
            let fresh = inspection.candidate
            let freshFingerprint = TrustFingerprint(candidate: fresh)

            // Unchanged on-disk identity.
            if fresh == candidate {
                return confirmedFingerprints.contains(freshFingerprint) || isAutomaticallyTrusted(inspection)
            }

            // ChatGPT/Codex app updates keep the path but churn inode/hash.
            guard fresh.canonicalURL.path == candidate.canonicalURL.path else { return false }

            if isAutomaticallyTrusted(inspection) {
                eligibleFingerprints.insert(freshFingerprint)
                return true
            }

            // Previously confirmed at this path with the same signing identity — roll the fingerprint.
            guard fresh.signingIdentifier == candidate.signingIdentifier,
                  fresh.teamIdentifier == candidate.teamIdentifier,
                  confirmedFingerprints.contains(where: {
                      $0.canonicalPath == candidate.canonicalURL.path
                          && $0.signingIdentifier == candidate.signingIdentifier
                          && $0.teamIdentifier == candidate.teamIdentifier
                  })
            else { return false }

            eligibleFingerprints.insert(freshFingerprint)
            confirmedFingerprints.insert(freshFingerprint)
            onConfirmedFingerprintsChanged?(confirmedFingerprints)
            return true
        } catch {
            return false
        }
    }

    private func normalize(_ inspection: StaticExecutableInspection, input: ExecutablePathInput) -> StaticExecutableInspection {
        StaticExecutableInspection(
            candidate: ExecutableCandidate(
                canonicalURL: inspection.candidate.canonicalURL,
                source: input.source,
                ownerUID: inspection.candidate.ownerUID,
                mode: inspection.candidate.mode,
                signingIdentifier: inspection.candidate.signingIdentifier,
                teamIdentifier: inspection.candidate.teamIdentifier,
                codeHash: inspection.candidate.codeHash,
                deviceID: inspection.candidate.deviceID,
                inode: inspection.candidate.inode,
                inputURL: input.url
            ),
            signatureIsValid: inspection.signatureIsValid,
            bundleIdentifier: inspection.bundleIdentifier
        )
    }

    private func trust(for inspection: StaticExecutableInspection, fingerprint: TrustFingerprint) -> ExecutableTrust {
        if isAutomaticallyTrusted(inspection) {
            return .bundleAllowList
        }
        return confirmedFingerprints.contains(fingerprint) ? .confirmed : .requiresConfirmation
    }

    private func isAutomaticallyTrusted(_ inspection: StaticExecutableInspection) -> Bool {
        let candidate = inspection.candidate
        let expectedPath: String?
        switch candidate.source {
        case .chatGPTBundle:
            expectedPath = Self.chatGPTSystemPath
        case .codexBundle:
            expectedPath = Self.codexSystemPath
        default:
            expectedPath = nil
        }
        // ChatGPT.app is usually user-owned (not root). Allow the current user as well as root.
        let ownerOK = candidate.ownerUID == 0 || candidate.ownerUID == getuid()
        return expectedPath == candidate.canonicalURL.path &&
            ownerOK &&
            inspection.signatureIsValid &&
            inspection.bundleIdentifier == Self.allowedSigningIdentifier &&
            inspection.candidate.signingIdentifier == Self.allowedSigningIdentifier &&
            inspection.candidate.teamIdentifier == Self.allowedTeamIdentifier
    }
}
