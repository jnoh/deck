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

    /// Load configs from both bundled templates and user directory.
    /// User configs override bundled ones with the same name.
    public static func loadAll(from directory: URL = defaultConfigDirectory) throws -> [SessionConfig] {
        try ensureConfigDirectory(at: directory)

        var configsByName: [String: SessionConfig] = [:]

        // 1. Load bundled templates from app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let templatesDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("templates")
            if FileManager.default.fileExists(atPath: templatesDir.path) {
                for config in try loadFromDirectory(templatesDir) {
                    configsByName[config.name] = config
                }
            }
        }

        // 2. Load user configs — these override bundled ones
        for config in try loadFromDirectory(directory) {
            configsByName[config.name] = config
        }

        return configsByName.values.sorted { $0.name < $1.name }
    }

    private static func loadFromDirectory(_ directory: URL) throws -> [SessionConfig] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var configs: [SessionConfig] = []

        for item in contents where item.pathExtension == "deck" {
            let tomlFile = item.appendingPathComponent("session.toml")
            guard fm.fileExists(atPath: tomlFile.path) else { continue }
            let tomlString = try String(contentsOf: tomlFile, encoding: .utf8)
            var config = try SessionConfig.parse(from: tomlString, filePath: tomlFile)
            config.packageDir = item
            configs.append(config)
        }

        return configs
    }
}
