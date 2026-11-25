import AppKit
import Carbon
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: ShelfStore, login: LoginItemController, prefs: AppPreferences) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(store: store, login: login, prefs: prefs)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "Centik Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 370))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var login: LoginItemController
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        Form {
            Section("Shortcut") {
                Toggle("Global Shortcut", isOn: $prefs.hotKeyEnabled)
                HStack {
                    Text("Toggle Shelf")
                    Spacer()
                    ShortcutRecorderButton(combo: $prefs.hotKey, disabled: !prefs.hotKeyEnabled)
                    if prefs.hotKey != .defaultCombo {
                        Button("Reset") {
                            prefs.hotKey = .defaultCombo
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Display") {
                Picker("Show Shelf On", selection: $prefs.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Show Top Pill on Non-Notch Displays", isOn: $prefs.showPillOnNonNotch)
                Text("When turned off, Centik stays invisible on non-notch screens until you hover or drag to the top center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Files") {
                Picker("When Dropping Files", selection: $prefs.fileMode) {
                    ForEach(ShelfFileMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(prefs.fileMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Remove After Copy-Drag", isOn: $store.removeAfterDrag)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                if login.needsApproval {
                    Button("Approve in System Settings…") {
                        login.openSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 370)
    }
}

private struct ShortcutRecorderButton: View {
    @Binding var combo: HotKeyCombo
    var disabled: Bool

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if recording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(recording ? "Press keys…" : combo.displayString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(minWidth: 78)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .disabled(disabled)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMods = HotKeyCombo.carbonModifiers(from: flags)
            // Require at least one modifier (Cmd, Opt, Ctrl, or Shift) so plain typing isn't captured.
            guard carbonMods != 0 else {
                NSSound.beep()
                return nil
            }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
