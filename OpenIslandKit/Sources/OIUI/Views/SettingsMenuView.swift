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
        setupActions: ProviderSetupActions? = nil,
    ) {
        self.viewModel = viewModel
        self.onCheckForUpdates = onCheckForUpdates
        self.updateStatusContent = updateStatusContent
        self.setupActions = setupActions
    }

    // MARK: Package

    package var body: some View {
        Group {
            if let activeSetupProvider = self.setupSheetProvider, let setupActions {
                ProviderSetupSheetView(
                    providerID: activeSetupProvider,
                    setupActions: setupActions,
                ) {
                    self.setupSheetProvider = nil
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        self.soundSection
                        SettingsDivider()
                        self.displaySection
                        SettingsDivider()
                        self.providersSection
                        SettingsDivider()
                        self.modulesSection
                        SettingsDivider()
                        self.aboutSection
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear { self.loadSettings() }
        .task { await self.refreshProviderStatuses() }
        .alert(
            "Disable Provider",
            isPresented: Binding(
                get: { self.disableConfirmationProvider != nil },
                set: { if !$0 { self.disableConfirmationProvider = nil } },
            ),
        ) {
            Button("Disable Only", role: .destructive) {
                if let provider = self.disableConfirmationProvider {
                    self.performDisable(provider, removeHooks: false)
                }
            }
            Button("Disable & Remove Hooks", role: .destructive) {
                if let provider = self.disableConfirmationProvider {
                    self.performDisable(provider, removeHooks: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let provider = self.disableConfirmationProvider {
                let name = ProviderMetadata.metadata(for: provider).displayName
                Text("\(name) has installed hooks. Do you also want to remove them?")
            }
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    // MARK: Sound state

    @State private var notificationSound: NotificationSound = .default
    @State private var soundSuppression: SoundSuppression = .whenFocused

    // MARK: Display state

    @State private var mascotColor: Color = AppSettings.brandTeal
    @State private var mascotAlwaysVisible = true
    @State private var notchAutoExpand = true

    // MARK: Providers state

    @State private var enabledProviders: Set<ProviderID> = AppSettings.enabledProviders
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

    // MARK: Setup sheet state

    @State private var setupSheetProvider: ProviderID?

    // MARK: Disable confirmation state

    @State private var disableConfirmationProvider: ProviderID?
    @State private var removeHooksOnDisable = false

    // MARK: Provider status state

    @State private var providerStatuses: [ProviderID: ProviderInstallationStatus] = [:]

    private var viewModel: NotchViewModel
    private var onCheckForUpdates: (() -> Void)?
    private var updateStatusContent: AnyView?
    private var setupActions: ProviderSetupActions?

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
        SettingsSection(title: "Sound", icon: "speaker.wave.2") {
            VStack(spacing: 2) {
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
        SettingsSection(title: "Display", icon: "paintbrush") {
            VStack(spacing: 2) {
                SettingsColorRow(
                    label: "Mascot Color",
                    selection: Binding(
                        get: { self.mascotColor },
                        set: {
                            self.mascotColor = $0
                            AppSettings.mascotColor = $0
                            self.viewModel.mascotColor = $0
                        },
                    ),
                )

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
        SettingsSection(title: "Providers", icon: "puzzlepiece.extension") {
            VStack(spacing: 4) {
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
        SettingsSection(title: "Modules", icon: "square.grid.2x2") {
            ModuleLayoutSettingsView(registry: self.viewModel.registry)
        }
    }

    // MARK: - About Section

    var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle") {
            VStack(spacing: 2) {
                SettingsInfoRow(label: "Version", value: self.appVersion)
                SettingsInfoRow(label: "Build", value: self.buildNumber)

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
            hasSetupActions: self.setupActions != nil,
            status: self.providerStatuses[providerID],
            onSetup: { self.setupSheetProvider = providerID },
            onToggle: { newValue in self.handleProviderToggle(providerID, enabled: newValue) },
            config: { self.providerConfig(for: providerID) },
        )
    }

    func providerConfig(for providerID: ProviderID) -> some View {
        VStack(spacing: 6) {
            Divider()
                .background(Color.white.opacity(0.08))

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
        .padding(.leading, 28)
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

    // MARK: - Provider Toggle

    func handleProviderToggle(_ providerID: ProviderID, enabled: Bool) {
        guard let setupActions else {
            // No setup actions — just toggle the setting.
            if enabled {
                self.enabledProviders.insert(providerID)
            } else {
                self.enabledProviders.remove(providerID)
            }
            AppSettings.enabledProviders = self.enabledProviders
            return
        }

        if enabled {
            // Enable: optimistically update UI, persist only after successful start.
            self.enabledProviders.insert(providerID)
            self.providerStatuses[providerID] = .installing
            Task {
                do {
                    try await setupActions.enableProvider(providerID)
                    self.providerStatuses[providerID] = .installed
                } catch {
                    // Revert: provider failed to start, undo the optimistic UI update.
                    self.enabledProviders.remove(providerID)
                    self.providerStatuses[providerID] = .failed(error)
                }
            }
        } else {
            // Disable: check if this is a hook-based provider that might need hook removal.
            let meta = ProviderMetadata.metadata(for: providerID)
            if meta.transportType == .hookSocket {
                self.disableConfirmationProvider = providerID
            } else {
                self.performDisable(providerID, removeHooks: false)
            }
        }
    }

    func performDisable(_ providerID: ProviderID, removeHooks: Bool) {
        self.enabledProviders.remove(providerID)
        AppSettings.enabledProviders = self.enabledProviders

        guard let setupActions else { return }
        Task {
            await setupActions.disableProvider(providerID)
            if removeHooks {
                do {
                    try await setupActions.uninstall(providerID)
                    self.providerStatuses[providerID] = .notInstalled
                } catch {
                    self.providerStatuses[providerID] = .failed(error)
                }
            } else {
                self.providerStatuses[providerID] = .notInstalled
            }
        }
    }

    func refreshProviderStatuses() async {
        guard let setupActions else { return }
        for providerID in ProviderID.allKnown {
            let running = await setupActions.isProviderRunning(providerID)
            if running {
                self.providerStatuses[providerID] = .installed
            } else if self.enabledProviders.contains(providerID) {
                // Enabled but not running — may have failed to start.
                self.providerStatuses[providerID] = .notInstalled
            } else {
                self.providerStatuses[providerID] = .notInstalled
            }
        }
    }
}

// MARK: - ProviderRowView

/// Provider row with hover highlight, expand/collapse config, status dot, and optional setup button.
private struct ProviderRowView<Config: View>: View {
    // MARK: Internal

    let providerID: ProviderID
    @Binding var enabledProviders: Set<ProviderID>
    @Binding var expandedProvider: ProviderID?

    let reduceMotion: Bool
    let viewModel: NotchViewModel
    var hasSetupActions = false
    var status: ProviderInstallationStatus?
    var onSetup: (() -> Void)?
    var onToggle: ((Bool) -> Void)?
    @ViewBuilder let config: Config

    var body: some View {
        let meta = ProviderMetadata.metadata(for: self.providerID)
        let isEnabled = self.enabledProviders.contains(self.providerID)
        let isExpanded = self.expandedProvider == self.providerID

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: meta.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: meta.accentColorHex) ?? .white)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(meta.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(self.isHovered ? 1.0 : 0.85))

                ProviderStatusDot(status: self.status)

                Spacer()

                if self.hasSetupActions {
                    ProviderSetupButton(
                        providerID: self.providerID,
                        onSetup: self.onSetup ?? {},
                    )
                }

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if let onToggle {
                            onToggle(newValue)
                        } else {
                            if newValue {
                                self.enabledProviders.insert(self.providerID)
                            } else {
                                self.enabledProviders.remove(self.providerID)
                            }
                            AppSettings.enabledProviders = self.enabledProviders
                        }
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
            .padding(.vertical, 10)
            .padding(.horizontal, 12)

            if isExpanded {
                self.config
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(self.isHovered ? 0.08 : 0.03)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - ProviderStatusDot

/// Colored dot indicating provider installation/running status.
private struct ProviderStatusDot: View {
    // MARK: Internal

    let status: ProviderInstallationStatus?

    var body: some View {
        Circle()
            .fill(self.dotColor)
            .frame(width: 6, height: 6)
            .accessibilityLabel(self.accessibilityText)
    }

    // MARK: Private

    private var dotColor: Color {
        switch self.status {
        case .installed:
            .green
        case .installing:
            .yellow
        case .failed:
            .red
        case .notInstalled,
             .none:
            .white.opacity(0.2)
        }
    }

    private var accessibilityText: String {
        switch self.status {
        case .installed:
            "Running"
        case .installing:
            "Starting"
        case .failed:
            "Error"
        case .notInstalled,
             .none:
            "Not running"
        }
    }
}

// MARK: - ProviderSetupButton

/// Compact "Setup" button shown in the provider row when setup actions are available.
private struct ProviderSetupButton: View {
    // MARK: Internal

    let providerID: ProviderID
    let onSetup: () -> Void

    var body: some View {
        Button {
            self.onSetup()
        } label: {
            Text("Setup")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(self.isHovered ? 0.15 : 0.08)),
                )
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .accessibilityLabel("Setup \(ProviderMetadata.metadata(for: self.providerID).displayName)")
        .accessibilityHint("Opens the setup wizard for this provider")
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - ProviderID + Identifiable

extension ProviderID: Identifiable {
    package var id: String {
        self.rawValue
    }
}

// MARK: - ProviderSetupSheetView

/// Modal sheet for provider onboarding — shows prerequisites, setup steps, and installation progress.
private struct ProviderSetupSheetView: View {
    // MARK: Internal

    let providerID: ProviderID
    let setupActions: ProviderSetupActions
    let onDismiss: () -> Void

    var body: some View {
        let meta = ProviderMetadata.metadata(for: self.providerID)
        let accentColor = Color(hex: meta.accentColorHex) ?? .white

        VStack(spacing: 0) {
            self.sheetHeader(meta: meta, accentColor: accentColor)

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let requirements {
                        self.prerequisitesSection(requirements: requirements)
                        self.stepsSection(requirements: requirements)
                    }

                    if let errorMessage {
                        self.errorBanner(message: errorMessage)
                    }
                }
                .padding(20)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            self.sheetFooter(accentColor: accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await self.loadRequirements() }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    @State private var requirements: ProviderSetupRequirements?
    @State private var phase: SetupPhase = .idle
    @State private var progressMessage = ""
    @State private var errorMessage: String?

    // MARK: - Header

    private func sheetHeader(meta: ProviderMetadata, accentColor: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: meta.iconName)
                .font(.system(size: 18))
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Setup \(meta.displayName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let duration = self.requirements?.estimatedDuration {
                    Text("Estimated: \(duration)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                self.onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close setup sheet")
        }
        .padding(16)
    }

    // MARK: - Prerequisites Section

    private func prerequisitesSection(requirements: ProviderSetupRequirements) -> some View {
        Group {
            if !requirements.prerequisites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PREREQUISITES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(requirements.prerequisites, id: \.id) { prereq in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(prereq.description)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(prereq.checkDescription)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - Steps Section

    private func stepsSection(requirements: ProviderSetupRequirements) -> some View {
        Group {
            if !requirements.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SETUP STEPS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(requirements.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(step.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))

                                    if step.isDestructive {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.yellow)
                                            .accessibilityLabel("Destructive step")
                                    }
                                }

                                Text(step.description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)

                                if !step.affectedPaths.isEmpty {
                                    Text(step.affectedPaths.joined(separator: ", "))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.9))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.red.opacity(0.1)),
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup error: \(message)")
    }

    // MARK: - Footer

    private func sheetFooter(accentColor: Color) -> some View {
        HStack {
            if self.phase == .installing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(self.progressMessage.isEmpty ? "Installing…" : self.progressMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Installing: \(self.progressMessage)")
            } else if self.phase == .complete {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("Setup complete")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            if self.phase == .complete {
                Button("Done") {
                    self.onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.8)),
                )
                .accessibilityLabel("Close setup sheet")
            } else {
                Button("Install") {
                    self.runInstall()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(self.phase == .idle ? 0.8 : 0.4)),
                )
                .disabled(self.phase != .idle)
                .accessibilityLabel("Install \(ProviderMetadata.metadata(for: self.providerID).displayName)")
            }
        }
        .padding(16)
    }

    private func loadRequirements() async {
        self.requirements = await self.setupActions.requirements(self.providerID)
    }

    private func runInstall() {
        guard self.phase == .idle else { return }
        self.phase = .installing
        self.errorMessage = nil

        Task {
            do {
                try await self.setupActions.install(self.providerID) { message in
                    Task { @MainActor in
                        self.progressMessage = message
                    }
                }
                self.phase = .complete
            } catch {
                self.phase = .idle
                self.errorMessage = (error as? CustomStringConvertible)?.description
                    ?? error.localizedDescription
            }
        }
    }
}

// MARK: - SetupPhase

/// Local state for the setup sheet's installation progress.
private enum SetupPhase {
    case idle
    case installing
    case complete
}

// MARK: - SettingsSection

/// Grouped section with a header label and content.
private struct SettingsSection<Content: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(self.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
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
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(self.isHovered ? 0.08 : 0)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - SettingsTextField

/// Compact labeled text field with hover highlight.
private struct SettingsTextField: View {
    // MARK: Internal

    let label: String
    @Binding var text: String

    var placeholder = ""

    var body: some View {
        HStack {
            Text(self.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))
            Spacer()
            TextField(self.placeholder, text: self.$text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 160)
                .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(self.isHovered ? 0.08 : 0)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
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
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))
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
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(self.isHovered ? 0.08 : 0)),
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
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text("Check for Updates")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(self.isHovered ? 0.12 : 0.06)),
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

// MARK: - SettingsDivider

/// Subtle divider between sections.
private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.04))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

// MARK: - SettingsInfoRow

/// Read-only info row with label and value.
private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(self.label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(self.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

// MARK: - SettingsColorRow

/// Color picker row with hover highlight.
private struct SettingsColorRow: View {
    // MARK: Internal

    let label: String

    @Binding var selection: Color

    var body: some View {
        HStack {
            Text(self.label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(self.isHovered ? 0.9 : 0.7))

            Spacer()

            ColorPicker("", selection: self.$selection, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 24)
                .accessibilityLabel(self.label)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(self.isHovered ? 0.08 : 0)),
        )
        .onHover { self.isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}
