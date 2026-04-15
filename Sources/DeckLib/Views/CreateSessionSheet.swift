import SwiftUI
import AppKit

public struct CreateSessionSheet: View {
    let blueprint: SessionConfig
    let onCreate: (String, String, [String: String]) -> Void  // (name, workingDir, params)
    @Environment(\.dismiss) private var dismiss

    @State private var workingDir: String = ""
    @State private var paramValues: [String: String] = [:]

    public init(blueprint: SessionConfig, onCreate: @escaping (String, String, [String: String]) -> Void) {
        self.blueprint = blueprint
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading) {
                    Text("New \(blueprint.name) session")
                        .font(.headline)
                    if !blueprint.description.isEmpty {
                        Text(blueprint.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider()

            // Dynamic params from the TOML
            ForEach(blueprint.params, id: \.key) { param in
                LabeledContent(param.label) {
                    TextField(param.placeholder ?? "", text: binding(for: param.key))
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Directory picker (always shown)
            LabeledContent("Directory") {
                HStack {
                    TextField("~/projects/myapp", text: $workingDir)
                        .textFieldStyle(.roundedBorder)

                    if blueprint.type == .local {
                        Button("Browse...") {
                            browseDirectory()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let dir = workingDir.isEmpty ? blueprint.startup.workingDir : workingDir
                    onCreate(blueprint.name, dir, paramValues)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!allRequiredFilled)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            workingDir = blueprint.startup.workingDir
            for param in blueprint.params {
                paramValues[param.key] = param.defaultValue
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { paramValues[key] ?? "" },
            set: { paramValues[key] = $0 }
        )
    }

    private var allRequiredFilled: Bool {
        blueprint.params.allSatisfy { param in
            !param.isRequired || !(paramValues[param.key] ?? "").isEmpty
        }
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory"

        if let expanded = expandTilde(workingDir) {
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        if panel.runModal() == .OK, let url = panel.url {
            workingDir = url.path
        }
    }

    private func expandTilde(_ path: String) -> String? {
        if path.hasPrefix("~/") || path == "~" {
            return NSString(string: path).expandingTildeInPath
        }
        return path.isEmpty ? nil : path
    }
}
