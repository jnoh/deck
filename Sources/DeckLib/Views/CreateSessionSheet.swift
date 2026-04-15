import SwiftUI
import AppKit

public struct CreateSessionSheet: View {
    let blueprint: SessionConfig
    let onCreate: (String, String) -> Void  // (sessionName, workingDir)
    @Environment(\.dismiss) private var dismiss

    @State private var workingDir: String = ""

    public init(blueprint: SessionConfig, onCreate: @escaping (String, String) -> Void) {
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
                    onCreate(blueprint.name, dir)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            workingDir = blueprint.startup.workingDir
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
