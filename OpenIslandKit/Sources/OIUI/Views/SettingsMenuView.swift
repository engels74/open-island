// swiftlint:disable file_length
import OICore
import OIModules
package import SwiftUI

// MARK: - SettingsMenuView

/// Full settings menu displayed inside the opened notch panel.
///
/// Sections: Sound, Display, Providers, Modules, About.
/// Uses `@State` variables synced with `AppSettings` static properties
/// because SwiftUI bindings require instance storage.
package struct SettingsMenuView: View {
    // MARK: Lifecycle

    package init(
        viewModel: NotchViewModel,
        onCheckForUpdates: (() -> Void)? = nil,
        updateStatusContent: AnyView? = nil,
    ) {
        self.viewModel = viewModel
        self.onCheckForUpdates = onCheckForUpdates
        self.updateStatusContent = updateStatusContent
    }

    // MARK: Package

    package var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                self.soundSection
                self.displaySection
                self.providersSection
                self.modulesSection
                self.aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { self.loadSettings() }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    // MARK: Sound state

    @State private var notificationSound: NotificationSound = .default
    @State private var soundSuppression: SoundSuppression = .whenFocused

    // MARK: Display state

    @State private var mascotColor: Color = .orange
    @State private var mascotAlwaysVisible = true
    @State private var notchAutoExpand = true

    // MARK: Providers state

    @State private var enabledProviders: Set<ProviderID> = Set(ProviderID.allKnown)
    @State private var expandedProvider: ProviderID?

    // MARK: Claude provider state

    @State private var claudeHookPath = ""

    // MARK: Codex provider state

    @State private var codexBinaryPath = ""
    @State private var codexApprovalPolicy = ""

    // MARK: Gemini provider state

    @State private var geminiHookPath = ""
    @State private var geminiThrottleMs = ""

    // MARK: OpenCode provider state

    @State private var openCodePort = ""
    @State private var openCodeUseMDNS = false

    // MARK: About state

    @State private var verboseMode = false

    private var viewModel: NotchViewModel
    private var onCheckForUpdates: (() -> Void)?
    private var updateStatusContent: AnyView?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - SettingsMenuView + Sections

private extension SettingsMenuView {
    // MARK: - Sound Section

    var soundSection: some View {
        SettingsSection(title: "Sound") {
            VStack(spacing: 8) {
                LabeledPicker(
                    label: "Notification Sound",
                    selection: Binding(
                        get: { self.notificationSound },
                        set: {
                            self.notificationSound = $0
                            AppSettings.notificationSound = $0
                        },
                    ),
                    options: NotificationSound.allCases,
                ) { sound in
                    switch sound {
                    case .default: "Default"
                    case .subtle: "Subtle"
                    case .chime: "Chime"
                    case .none: "None"
                    }
                }

                LabeledPicker(
                    label: "Suppress When",
                    selection: Binding(
                        get: { self.soundSuppression },
                        set: {
                            self.soundSuppression = $0
                            AppSettings.soundSuppression = $0
                        },
                    ),
                    options: SoundSuppression.allCases,
                ) { mode in
                    switch mode {
                    case .never: "Never"
                    case .whenFocused: "App Focused"
                    case .whenVisible: "Terminal Visible"
                    }
                }
            }
        }
    }

    // MARK: - Display Section

    var displaySection: some View {
        SettingsSection(title: "Display") {
            VStack(spacing: 8) {
                HStack {
                    Text("Mascot Color")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { self.mascotColor },
                            set: {
                                self.mascotColor = $0
                                AppSettings.mascotColor = $0
                            },
                        ),
                        supportsOpacity: false,
                    )
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Mascot Color")
                }

                SettingsToggle(
                    label: "Mascot Always Visible",
                    isOn: Binding(
                        get: { self.mascotAlwaysVisible },
                        set: {
                            self.mascotAlwaysVisible = $0
                            AppSettings.mascotAlwaysVisible = $0
                        },
                    ),
                )

                SettingsToggle(
                    label: "Auto-Expand on Events",
                    isOn: Binding(
                        get: { self.notchAutoExpand },
                        set: {
                            self.notchAutoExpand = $0
                            AppSettings.notchAutoExpand = $0
                        },
                    ),
                )
            }
        }
    }

    // MARK: - Providers Section

    var providersSection: some View {
        SettingsSection(title: "Providers") {
            VStack(spacing: 6) {
                ForEach(ProviderID.allKnown, id: \.rawValue) { providerID in
                    self.providerRow(providerID)
                }
            }
        }
    }

    var claudeConfig: some View {
        VStack(spacing: 6) {
            SettingsTextField(
                label: "Hook Path",
                text: Binding(
                    get: { self.claudeHookPath },
                    set: {
                        self.claudeHookPath = $0
                        AppSettings.Claude.hookPath = $0.isEmpty ? nil : $0
                    },
                ),
                placeholder: "~/.claude/hooks",
            )

            HStack(spacing: 4) {
                Circle()
                    .fill(AppSettings.Claude.hookPath != nil ? .green : .yellow)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(AppSettings.Claude.hookPath != nil ? "Hook configured" : "Not configured")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AppSettings.Claude.hookPath != nil ? "Hook configured" : "Hook not configured")
        }
    }

    var codexConfig: some View {
        VStack(spacing: 6) {
            SettingsTextField(
                label: "App-Server Binary",
                text: Binding(
                    get: { self.codexBinaryPath },
                    set: {
                        self.codexBinaryPath = $0
                        AppSettings.Codex.appServerBinary = $0.isEmpty ? nil : $0
                    },
                ),
                placeholder: "/usr/local/bin/codex",
            )

            HStack {
                Text("Approval Policy")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { self.codexApprovalPolicy },
                    set: {
                        self.codexApprovalPolicy = $0
                        AppSettings.Codex.approvalPolicy = $0.isEmpty ? nil : $0
                    },
                )) {
                    Text("Default").tag("")
                    Text("Suggest").tag("suggest")
                    Text("Auto-Edit").tag("auto-edit")
                    Text("Full-Auto").tag("full-auto")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
        }
    }

    var geminiConfig: some View {
        VStack(spacing: 6) {
            SettingsTextField(
                label: "Hook Path",
                text: Binding(
                    get: { self.geminiHookPath },
                    set: {
                        self.geminiHookPath = $0
                        AppSettings.GeminiCLI.hookPath = $0.isEmpty ? nil : $0
                    },
                ),
                placeholder: "~/.gemini/hooks",
            )

            HStack {
                Text("Throttle (ms)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("ms", text: self.$geminiThrottleMs)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.system(size: 10))
                    .controlSize(.small)
                    .onSubmit {
                        AppSettings.GeminiCLI.throttleAfterModelMs = self.geminiThrottleMs.isEmpty
                            ? nil
                            : Int(self.geminiThrottleMs)
                    }
            }
        }
    }

    var openCodeConfig: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Server Port")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("port", text: self.$openCodePort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.system(size: 10))
                    .controlSize(.small)
                    .onSubmit {
                        AppSettings.OpenCode.serverPort = self.openCodePort.isEmpty
                            ? nil
                            : Int(self.openCodePort)
                    }
            }

            SettingsToggle(
                label: "mDNS Discovery",
                isOn: Binding(
                    get: { self.openCodeUseMDNS },
                    set: {
                        self.openCodeUseMDNS = $0
                        AppSettings.OpenCode.useMDNS = $0
                    },
                ),
            )
        }
    }

    // MARK: - Modules Section

    var modulesSection: some View {
        SettingsSection(title: "Modules") {
            ModuleLayoutSettingsView(registry: self.viewModel.registry)
        }
    }

    // MARK: - About Section

    var aboutSection: some View {
        SettingsSection(title: "About") {
            VStack(spacing: 6) {
                HStack {
                    Text("Version")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(self.appVersion)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack {
                    Text("Build")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(self.buildNumber)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                SettingsToggle(
                    label: "Verbose Logging",
                    isOn: Binding(
                        get: { self.verboseMode },
                        set: {
                            self.verboseMode = $0
                            AppSettings.verboseMode = $0
                        },
                    ),
                )

                if let updateStatusContent {
                    updateStatusContent
                }

                if let onCheckForUpdates {
                    UpdateButton(action: onCheckForUpdates)
                }
            }
        }
    }

    // MARK: - Provider Row & Config

    func providerRow(_ providerID: ProviderID) -> some View {
        ProviderRowView(
            providerID: providerID,
            enabledProviders: self.$enabledProviders,
            expandedProvider: self.$expandedProvider,
            reduceMotion: self.reduceMotion,
            viewModel: self.viewModel,
        ) {
            self.providerConfig(for: providerID)
        }
    }

    func providerConfig(for providerID: ProviderID) -> some View {
        VStack(spacing: 6) {
            Divider().opacity(0.3)

            switch providerID {
            case .claude:
                self.claudeConfig
            case .codex:
                self.codexConfig
            case .geminiCLI:
                self.geminiConfig
            case .openCode:
                self.openCodeConfig
            case .example: EmptyView()
            }
        }
    }

    // MARK: - Load / Sync

    func loadSettings() {
        self.notificationSound = AppSettings.notificationSound
        self.soundSuppression = AppSettings.soundSuppression
        self.mascotColor = AppSettings.mascotColor
        self.mascotAlwaysVisible = AppSettings.mascotAlwaysVisible
        self.notchAutoExpand = AppSettings.notchAutoExpand
        self.enabledProviders = AppSettings.enabledProviders
        self.verboseMode = AppSettings.verboseMode
        self.claudeHookPath = AppSettings.Claude.hookPath ?? ""
        self.codexBinaryPath = AppSettings.Codex.appServerBinary ?? ""
        self.codexApprovalPolicy = AppSettings.Codex.approvalPolicy ?? ""
        self.geminiHookPath = AppSettings.GeminiCLI.hookPath ?? ""
        self.geminiThrottleMs = AppSettings.GeminiCLI.throttleAfterModelMs.map(String.init) ?? ""
        self.openCodePort = AppSettings.OpenCode.serverPort.map(String.init) ?? ""
        self.openCodeUseMDNS = AppSettings.OpenCode.useMDNS
    }
}

// MARK: - ProviderRowView

/// Provider row with hover highlight and expand/collapse config.
private struct ProviderRowView<Config: View>: View {
    // MARK: Internal

    let providerID: ProviderID
    @Binding var enabledProviders: Set<ProviderID>
    @Binding var expandedProvider: ProviderID?

    let reduceMotion: Bool
    let viewModel: NotchViewModel
    @ViewBuilder let config: Config

    var body: some View {
        let meta = ProviderMetadata.metadata(for: self.providerID)
        let isEnabled = self.enabledProviders.contains(self.providerID)
        let isExpanded = self.expandedProvider == self.providerID

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: meta.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: meta.accentColorHex) ?? .white)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(meta.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(self.isHovered ? 1.0 : 0.85))
                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            self.enabledProviders.insert(self.providerID)
                        } else {
                            self.enabledProviders.remove(self.providerID)
                        }
                        AppSettings.enabledProviders = self.enabledProviders
                    },
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Enable \(meta.displayName)")

                Button {
                    let newValue: ProviderID? = isExpanded ? nil : self.providerID
                    if self.reduceMotion {
                        self.expandedProvider = newValue
                    } else {
                        withAnimation(.smooth(duration: 0.25)) { self.expandedProvider = newValue }
                    }
                    self.viewModel.invalidateMenuLayout()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(meta.displayName) settings")
                .accessibilityHint(
                    isExpanded ? "Collapses provider configuration" : "Expands provider configuration",
                )
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            if isExpanded {
                self.config
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(self.isHovered ? 0.1 : 0.05)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - SettingsSection

/// Grouped section with a header label and content.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            self.content
        }
    }
}

// MARK: - SettingsToggle

/// Compact toggle row matching the notch aesthetic.
private struct SettingsToggle: View {
    // MARK: Internal

    let label: String

    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: self.$isOn) {
            Text(self.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.6))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(self.isHovered ? 0.06 : 0)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - SettingsTextField

/// Compact labeled text field.
private struct SettingsTextField: View {
    let label: String
    @Binding var text: String

    var placeholder = ""

    var body: some View {
        HStack {
            Text(self.label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            TextField(self.placeholder, text: self.$text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .frame(maxWidth: 160)
                .controlSize(.small)
        }
    }
}

// MARK: - LabeledPicker

/// Compact labeled picker for enum-backed settings.
private struct LabeledPicker<T: Hashable>: View {
    // MARK: Internal

    let label: String
    @Binding var selection: T

    let options: [T]
    let labelForOption: (T) -> String

    var body: some View {
        HStack {
            Text(self.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.6))
            Spacer()
            Picker("", selection: self.$selection) {
                ForEach(self.options, id: \.self) { option in
                    Text(self.labelForOption(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(self.isHovered ? 0.06 : 0)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - UpdateButton

/// Check for Updates button with hover highlight.
private struct UpdateButton: View {
    // MARK: Internal

    let action: () -> Void

    var body: some View {
        Button {
            self.action()
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                Text("Check for Updates")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(self.isHovered ? 0.12 : 0.08)),
            )
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .accessibilityLabel("Check for Updates")
        .accessibilityHint("Checks for new versions of Open Island")
    }

    // MARK: Private

    @State private var isHovered = false
}
