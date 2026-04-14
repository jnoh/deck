import Foundation

public struct ConfigLoader {
    public static let defaultConfigDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".deck/apps")
    }()

    public static func ensureConfigDirectory(at directory: URL = defaultConfigDirectory) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public static func loadAll(from directory: URL = defaultConfigDirectory) throws -> [SessionConfig] {
        try ensureConfigDirectory(at: directory)

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var configs: [SessionConfig] = []

        for item in contents {
            if item.pathExtension == "toml" {
                // Flat TOML blueprint
                let tomlString = try String(contentsOf: item, encoding: .utf8)
                let config = try SessionConfig.parse(from: tomlString, filePath: item)
                configs.append(config)

            } else if item.pathExtension == "deck" {
                // Directory package — read session.toml inside
                let tomlFile = item.appendingPathComponent("session.toml")
                guard fm.fileExists(atPath: tomlFile.path) else { continue }
                let tomlString = try String(contentsOf: tomlFile, encoding: .utf8)
                var config = try SessionConfig.parse(from: tomlString, filePath: tomlFile)
                config.packageDir = item
                configs.append(config)
            }
        }

        return configs.sorted { $0.name < $1.name }
    }
}
