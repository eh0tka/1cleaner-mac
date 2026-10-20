import Darwin
import Foundation
import os

/// Stopped containers, images that no container uses, volumes no container uses and the build cache, read from the
/// Docker CLI of the Docker on this Mac. The app never starts Docker.
struct DockerScanner: Scanner {
    static var executable: String? {
        ProcessRunner.firstExecutable([
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            NSHomeDirectory() + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ])
    }

    var categories: [CategoryID] { [.docker] }

    /// The Docker daemon the last scan read, always a socket on this Mac. Docker items are removed only through it:
    /// a remote context would make 1Cleaner list and remove another computer's data.
    static let scannedHost = OSAllocatedUnfairLock<String?>(initialState: nil)
    /// When the containers were listed: a container that ran after that isn't the one the list showed.
    static let scannedAt = OSAllocatedUnfairLock<Date?>(initialState: nil)

    /// The daemon Docker commands go to right now, when it is on this Mac (`unix://` socket); nil for a remote one.
    static func localHost(_ docker: String) async -> String? {
        if let host = ProcessInfo.processInfo.environment["DOCKER_HOST"], !host.isEmpty {
            return host.hasPrefix("unix://") ? host : nil
        }
        guard let result = try? await ProcessRunner.run(
            docker, ["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], timeout: .seconds(20)
        ), result.succeeded else { return nil }
        let host = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.hasPrefix("unix://") ? host : nil
    }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        [.docker: await scanDocker()]
    }

    private func scanDocker() async -> ScanOutput {
        guard let docker = Self.executable else {
            return ScanOutput(notes: [String(localized: "Docker isn't installed.", comment: "Note in the Docker category")])
        }
        Self.scannedHost.withLock { $0 = nil }
        guard let host = await Self.localHost(docker) else {
            return ScanOutput(notes: [String(localized: "Docker is set to use another computer. 1Cleaner cleans only Docker on this Mac.",
                                             comment: "Note in the Docker category when the Docker context points to a remote daemon")])
        }
        guard let info = try? await run(docker, host, ["info", "--format", "{{.ServerVersion}}"]), info.succeeded else {
            return ScanOutput(notes: [String(localized: "Docker isn't running. Start Docker and scan again to see its containers and images.",
                                             comment: "Note in the Docker category")])
        }
        Self.scannedHost.withLock { $0 = host }
        Self.scannedAt.withLock { $0 = Date() }
        var output = ScanOutput()

        // Stopped containers. Their size is the container's own writable layer.
        if let result = try? await run(docker, host, [
            "ps", "-a", "--no-trunc", "--size",
            "--filter", "status=exited", "--filter", "status=created", "--filter", "status=dead",
            "--format", "{{json .}}",
        ]), result.succeeded {
            for container in decodeLines(Container.self, result.stdout) {
                output.items.append(CleanupItem(
                    id: "docker:container:\(container.ID)",
                    category: .docker,
                    title: container.Names,
                    badge: String(localized: "Container", comment: "Badge of a stopped Docker container"),
                    detail: "\(container.Image) · \(container.Status)",
                    size: Self.parseSize(container.Size ?? "0B"),
                    removal: .docker(.container(container.ID))
                ))
            }
        }

        // Which containers use which image: images of running containers are never offered; images used only
        // by stopped containers are offered together with those containers.
        var runningImages = Set<String>()
        var stoppedByImage: [String: [(id: String, name: String)]] = [:]
        // Images are listed only when it's known which containers use them (a container removed between the two
        // calls fails the second one: scan again).
        var usageKnown = false
        if let ids = try? await run(docker, host, ["ps", "-a", "-q", "--no-trunc"]), ids.succeeded {
            let containerIDs = ids.stdout.split(whereSeparator: \.isNewline).map(String.init)
            usageKnown = containerIDs.isEmpty
            if !containerIDs.isEmpty, let inspected = try? await run(
                docker, host, ["inspect", "--format", "{{.Id}}|{{.Image}}|{{.State.Running}}|{{.Name}}"] + containerIDs
            ), inspected.succeeded {
                usageKnown = true
                for line in inspected.stdout.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count == 4 else { continue }
                    if parts[2] == "true" {
                        runningImages.insert(parts[1])
                    } else {
                        let name = parts[3].hasPrefix("/") ? String(parts[3].dropFirst()) : parts[3]
                        stoppedByImage[parts[1], default: []].append((parts[0], name))
                    }
                }
            }
        }
        if usageKnown, let result = try? await run(docker, host, ["image", "ls", "--no-trunc", "--format", "{{json .}}"]),
           result.succeeded {
            let images = decodeLines(Image.self, result.stdout)
            var references: [String: [String]] = [:]
            for image in images where image.Repository != "<none>" && image.Tag != "<none>" {
                references[image.ID, default: []].append("\(image.Repository):\(image.Tag)")
            }
            var seen = Set<String>()
            for image in images
            where !runningImages.contains(image.ID) && seen.insert(image.ID).inserted {
                let tagged = image.Repository != "<none>"
                let stopped = stoppedByImage[image.ID] ?? []
                // Docker's own "3 months ago" is English; the date itself is formatted in the app's language.
                let age = Self.date(image.CreatedAt)?.relativeDescription ?? image.CreatedSince ?? ""
                var detail = String(localized: "Created \(age)",
                                    comment: "Docker image detail; %@ is the image's age like '3 months ago'")
                if !stopped.isEmpty {
                    let names = stopped.map(\.name).joined(separator: ", ")
                    detail += " · " + (stopped.count == 1
                        ? String(localized: "also removes stopped container \(names)",
                                 comment: "Docker image detail; %@ is a container name")
                        : String(localized: "also removes stopped containers \(names)",
                                 comment: "Docker image detail; %@ is a comma-separated list of container names"))
                }
                output.items.append(CleanupItem(
                    id: "docker:image:\(image.ID)",
                    category: .docker,
                    title: tagged ? "\(image.Repository):\(image.Tag)"
                        : String(localized: "Untagged image", comment: "Title of a Docker image without a name"),
                    badge: String(localized: "Image", comment: "Badge of a Docker image"),
                    detail: detail,
                    size: Self.parseSize(image.Size ?? "0B"),
                    removal: .docker(.image(image.ID, stoppedContainers: stopped.map(\.id),
                                            references: references[image.ID] ?? []))
                ))
            }
        }

        // Disk usage per type, build cache and volumes no container uses (listed with a red
        // warning, never preselected; a volume can hold a database).
        var summary: [String] = []
        if let result = try? await run(docker, host, ["system", "df", "--format", "{{json .}}"]), result.succeeded {
            let rows = decodeLines(DiskUsageRow.self, result.stdout)
            for row in rows {
                let size = Self.parseSize(row.Size ?? "0B").formattedBytes
                // Docker's own type names; an unknown one is shown as Docker reports it.
                let part: String = switch row.TypeName {
                case "Images":
                    String(localized: "images \(size)", comment: "Part of the Docker summary list; %@ is a size like '1.2 GB'")
                case "Containers":
                    String(localized: "containers \(size)", comment: "Part of the Docker summary list; %@ is a size like '1.2 GB'")
                case "Local Volumes":
                    String(localized: "local volumes \(size)", comment: "Part of the Docker summary list; %@ is a size like '1.2 GB'")
                case "Build Cache":
                    String(localized: "build cache \(size)", comment: "Part of the Docker summary list; %@ is a size like '1.2 GB'")
                default:
                    "\(row.TypeName.lowercased()) \(size)"
                }
                summary.append(part)
            }
            // `docker system df` reports only part of the build cache as "reclaimable", but `builder prune --all`
            // removes every record no running build uses, so the item shows the whole cache size.
            if let row = rows.first(where: { $0.TypeName == "Build Cache" }) {
                let size = Self.parseSize(row.Size ?? row.Reclaimable ?? "0B")
                if size > 0 {
                    output.items.append(CleanupItem(
                        id: "docker:buildcache",
                        category: .docker,
                        title: String(localized: "Build cache", comment: "Title of Docker's build cache row"),
                        badge: String(localized: "Cache", comment: "Badge of Docker's build cache row"),
                        detail: String(localized: "Layers kept by docker build; the next build takes longer",
                                       comment: "Detail of Docker's build cache row; docker build is a command"),
                        size: size,
                        removal: .docker(.buildCache)
                    ))
                }
            }
        }
        if let result = try? await run(docker, host, ["system", "df", "-v", "--format", "{{json .Volumes}}"]), result.succeeded,
           let volumes = try? JSONDecoder().decode([Volume].self, from: Data(result.stdout.utf8)) {
            let unused = volumes.filter { $0.Links == "0" }
            // Each volume's creation time, so removal can tell it's still the same volume; none listed without it.
            var created: [String: String] = [:]
            if !unused.isEmpty, let inspected = try? await run(
                docker, host, ["volume", "inspect", "--format", "{{.Name}}\t{{.CreatedAt}}"] + unused.map(\.Name)
            ), inspected.succeeded {
                for line in inspected.stdout.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                    if parts.count == 2, !parts[1].isEmpty { created[parts[0]] = parts[1] }
                }
            }
            for volume in unused {
                guard let createdAt = created[volume.Name] else { continue }
                let labels = volume.Labels ?? ""
                let project = labels.split(separator: ",")
                    .first { $0.hasPrefix("com.docker.compose.project=") }
                    .map { String($0.dropFirst("com.docker.compose.project=".count)) }
                let anonymous = labels.contains("com.docker.volume.anonymous")
                output.items.append(CleanupItem(
                    id: "docker:volume:\(volume.Name)",
                    category: .docker,
                    title: anonymous
                        ? String(localized: "Anonymous volume \(String(volume.Name.prefix(12)))",
                                 comment: "Title of an unnamed Docker volume; %@ is the start of its identifier")
                        : volume.Name,
                    badge: String(localized: "Volume", comment: "Badge of a Docker volume"),
                    detail: (project.map {
                        String(localized: "Compose project \($0)", comment: "Docker volume detail; %@ is a Compose project name") + " · "
                    } ?? "")
                        + String(localized: "no container uses it", comment: "Docker volume detail")
                        + " · " + String(localized: "may hold a database or uploads", comment: "Docker volume detail"),
                    size: Self.parseSize(volume.Size ?? "0B"),
                    removal: .docker(.volume(volume.Name, created: createdAt))
                ))
            }
        }

        // Docker Desktop keeps everything in one disk image on the Mac; its size is what Docker really takes.
        let diskImage = NSHomeDirectory() + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        var diskInfo = stat()
        if lstat(diskImage, &diskInfo) == 0 {
            summary.append(String(localized: "Docker Desktop's disk image takes \((Int64(diskInfo.st_blocks) * 512).formattedBytes) on this Mac",
                                  comment: "Part of the Docker summary list; %@ is a size like '60 GB'"))
        }
        output.items.sort { $0.size > $1.size }
        if !summary.isEmpty {
            output.summary = String(localized: "Docker uses: \(summary.joined(separator: ", ")).",
                                    comment: "Summary above the Docker list; %@ is a comma-separated list like 'images 3 GB, build cache 5 GB'")
        }
        output.notes.append(String(localized: "Docker Desktop may return freed space to macOS gradually.",
                                   comment: "Note in the Docker category"))
        return output
    }

    private func run(_ docker: String, _ host: String, _ arguments: [String]) async throws -> ProcessRunner.Output {
        try await ProcessRunner.run(docker, ["--host", host] + arguments, timeout: .seconds(30))
    }

    private func decodeLines<T: Decodable>(_ type: T.Type, _ text: String) -> [T] {
        text.split(whereSeparator: \.isNewline).compactMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    /// Docker's human sizes: "12.3kB", "1.2GB", "512MB (virtual 1.2GB)", "1.5GiB".
    static func parseSize(_ text: String) -> Int64 {
        let token = text.split(separator: " ").first.map(String.init) ?? ""
        let number = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(number.count).lowercased()
        guard let value = Double(number) else { return 0 }
        let multiplier: Double = switch unit {
        case "kb": 1e3
        case "mb": 1e6
        case "gb": 1e9
        case "tb": 1e12
        case "kib": 1024
        case "mib": 1_048_576
        case "gib": 1_073_741_824
        case "tib": 1_099_511_627_776
        default: 1
        }
        return Int64(value * multiplier)
    }

    private struct Container: Decodable {
        let ID: String
        let Names: String
        let Image: String
        let Status: String
        let Size: String?
    }

    /// Docker's `State.FinishedAt` ("2026-10-19T21:03:44.123456789Z"), to the second.
    static func finishedAt(_ text: String) -> Date? {
        guard text.count >= 19 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: String(text.prefix(19)) + "Z")
    }

    private struct Image: Decodable {
        let ID: String
        let Repository: String
        let Tag: String
        let Size: String?
        let CreatedSince: String?
        /// "2024-05-01 12:34:56 +0300 MSK"
        let CreatedAt: String?
    }

    /// Docker's `CreatedAt`, without the trailing zone name.
    static func date(_ text: String?) -> Date? {
        guard let text, text.count >= 25 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: String(text.prefix(25)))
    }

    private struct Volume: Decodable {
        let Name: String
        let Links: String?
        let Size: String?
        let Labels: String?
    }

    private struct DiskUsageRow: Decodable {
        let TypeName: String
        let Size: String?
        let Reclaimable: String?

        enum CodingKeys: String, CodingKey {
            case TypeName = "Type"
            case Size
            case Reclaimable
        }
    }
}
