import SwiftUI

// MARK: - Select param loading state

private enum SelectState {
    case loading
    case loaded([ParamOption])
    case error(String)
}

public struct CreateSessionSheet: View {
    let blueprint: SessionConfig
    let onCreate: (String, [String: String]) -> Void  // (name, params)
    @Environment(\.dismiss) private var dismiss

    @State private var paramValues: [String: String] = [:]
    @State private var selectStates: [String: SelectState] = [:]

    public init(blueprint: SessionConfig, onCreate: @escaping (String, [String: String]) -> Void) {
        self.blueprint = blueprint
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading) {
                    Text("New \(blueprint.displayName) session")
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
                if param.isSelect {
                    selectParamView(param)
                } else {
                    LabeledContent(param.label) {
                        TextField(param.placeholder ?? "", text: binding(for: param.key))
                            .textFieldStyle(.roundedBorder)
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
                    onCreate(blueprint.name, paramValues)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            for param in blueprint.params {
                paramValues[param.key] = param.defaultValue
            }
            loadSelectParams()
        }
    }

    // MARK: - Select param view

    @ViewBuilder
    private func selectParamView(_ param: SessionParam) -> some View {
        let state = selectStates[param.key] ?? .loading

        LabeledContent(param.label) {
            switch state {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(param.placeholder ?? "Loading...")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .loaded(let options):
                Picker("", selection: binding(for: param.key)) {
                    if paramValues[param.key]?.isEmpty ?? true {
                        Text(param.placeholder ?? "Select...").tag("")
                    }
                    ForEach(options) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()

            case .error(let message):
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button("Retry") {
                        loadSelectParam(param)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Source loading

    private func loadSelectParams() {
        for param in blueprint.params where param.isSelect {
            loadSelectParam(param)
        }
    }

    private func loadSelectParam(_ param: SessionParam) {
        guard let source = param.source else {
            selectStates[param.key] = .error("No source command defined")
            return
        }

        selectStates[param.key] = .loading
        paramValues[param.key] = ""

        Task {
            // Collect already-filled upstream param values
            var upstreamEnv: [String: String] = [:]
            for p in blueprint.params {
                if p.key == param.key { break }
                if let val = paramValues[p.key], !val.isEmpty {
                    upstreamEnv[p.key] = val
                }
            }

            do {
                let options = try await ParamSourceRunner.run(
                    command: source,
                    packageDir: blueprint.packageDir,
                    environment: upstreamEnv
                )
                await MainActor.run {
                    selectStates[param.key] = .loaded(options)
                    // Pre-select default if it matches
                    if let defaultVal = param.default,
                       options.contains(where: { $0.value == defaultVal }) {
                        paramValues[param.key] = defaultVal
                    } else if options.count == 1 {
                        // Auto-select if only one option
                        paramValues[param.key] = options[0].value
                    }
                }
            } catch {
                await MainActor.run {
                    selectStates[param.key] = .error(String(describing: error))
                }
            }
        }
    }

    // MARK: - Helpers

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { paramValues[key] ?? "" },
            set: { paramValues[key] = $0 }
        )
    }

    private var canCreate: Bool {
        let textOk = blueprint.params
            .filter { !$0.isSelect }
            .allSatisfy { !$0.isRequired || !(paramValues[$0.key] ?? "").isEmpty }

        let selectOk = blueprint.params
            .filter { $0.isSelect }
            .allSatisfy { param in
                if !param.isRequired { return true }
                guard case .loaded = selectStates[param.key] else { return false }
                return !(paramValues[param.key] ?? "").isEmpty
            }

        return textOk && selectOk
    }
}
