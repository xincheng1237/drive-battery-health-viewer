import SwiftUI

@main
struct DriveBatteryHealthViewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 720, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        }
        .defaultSize(width: 1280, height: 780)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(model.t("menuEdit")) {
                Button(MainMenuLocalizer.marker(for: "menuEdit")) { }
                    .disabled(true)
            }
            CommandMenu(model.t("menuView")) {
                Button(MainMenuLocalizer.marker(for: "menuView")) { }
                    .disabled(true)
            }
            CommandMenu(model.t("report")) {
                Button(model.t("refresh")) { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning)
                Button(model.t("copyReport")) { model.copyCurrentReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.currentSnapshot == nil)
            }
            CommandMenu(model.t("menuWindow")) {
                Button(MainMenuLocalizer.marker(for: "menuWindow")) { }
                    .disabled(true)
            }
            CommandMenu(model.t("menuHelp")) {
                Button(MainMenuLocalizer.marker(for: "menuHelp")) { }
                    .disabled(true)
            }
        }
    }
}
