//
//  AppDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import SwiftUI
import Swinject

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    
    @IBOutlet weak var menu: NSMenu?
    
    var preferencesWindow: NSWindow?
    private var menuBarWindowControllers: [UInt64: MenuBarWindowController] = [:]
    private var spaceChangeObserver: NSObjectProtocol?
    private var spaceReconciliationTimer: Timer?
        
    override init() {
        super.init()
        
        Dependencies.setup()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        showMenuBarWindowForActiveSpace()

        spaceReconciliationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.showMenuBarWindowForActiveSpace()
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showMenuBarWindowForActiveSpace()
            }
        }
    }

    private func showMenuBarWindowForActiveSpace() {
        removeDeletedSpaceWindows()
        guard let spaceID = SpaceAPI.activeSpaceID,
              menuBarWindowControllers[spaceID] == nil,
              let mainScreen = NSScreen.main else {
            return
        }

        let menuBarWindow = MenuBarWindow(
            contentRect: NSRect(x: mainScreen.frame.minX,
                                y: mainScreen.frame.maxY - mainScreen.menuBarHeight - 1,
                                width: mainScreen.frame.width,
                                height: mainScreen.menuBarHeight + 1),
            styleMask: [
            ],
            backing: .buffered, defer: false)
        
        let controller = MenuBarWindowController(window: menuBarWindow)
        menuBarWindow.title = "ClearMenuBar overlay Space \(spaceID)"
        menuBarWindowControllers[spaceID] = controller
        menuBarWindow.orderFrontRegardless()
    }

    private func removeDeletedSpaceWindows() {
        guard let existingIDs = SpaceAPI.existingSpaceIDs else { return }
        for spaceID in Array(menuBarWindowControllers.keys) {
            let window = menuBarWindowControllers[spaceID]?.window
            let actualSpaces = window.flatMap { SpaceAPI.spacesForWindow($0.windowNumber) }
            // macOS can migrate a window while its originally assigned Space still
            // exists. Never leave that window blending over another Space's overlay.
            let misplaced = actualSpaces.map { !$0.isEmpty && $0 != Set([spaceID]) } ?? false
            guard !existingIDs.contains(spaceID) || misplaced else { continue }
            guard let controller = menuBarWindowControllers.removeValue(forKey: spaceID) else { continue }
            controller.window?.orderOut(nil)
            controller.window?.contentView = nil
            controller.close()
        }
    }

    @IBAction func about(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil) {
            
            var config = NSImage.SymbolConfiguration(textStyle: .body,
                                                     scale: .medium)
            config = config.applying(.init(pointSize: 15.0, weight: NSFont.Weight.regular))
            statusItem?.button?.image = image.withSymbolConfiguration(config)
        }
        
        if let menu = menu {
            statusItem?.menu = menu
        }
    }
    
    @IBAction func preferences(_ sender: Any?) {
        if (preferencesWindow == nil) {
            let preferencesView = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 570, height: 210),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.level = .floating
            preferencesWindow?.collectionBehavior = .canJoinAllSpaces
            preferencesWindow?.center()
            preferencesWindow?.title = "Clear Menu Bar Settings"
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.miniaturize(nil)
            preferencesWindow?.zoom(nil)
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        spaceReconciliationTimer?.invalidate()
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }

        guard let appState = Container.main.resolve(AppState.self),
              appState.allowReduceTransparencyToBeDisabled else {
            return
        }

        let spaceKey = SpaceAPI.activeSpaceID.map(String.init)
        let sources = UserDefaults.standard.dictionary(forKey: "sourceWallpapersBySpace") as? [String: String]
        let sourcePath = spaceKey.flatMap { sources?[$0] }
        let originalWallpaper = sourcePath.map(URL.init(fileURLWithPath:)) ?? appState.currentWallpaperPath

        if let originalWallpaper {
            try? Wallpaper.set(originalWallpaper, screen: .main)
        }

        let modifiedPaths = UserDefaults.standard.dictionary(forKey: "modifiedWallpapersBySpace") as? [String: String]
        let modifiedPath = spaceKey.flatMap { modifiedPaths?[$0] }
        if let modifiedWallpaper = modifiedPath.map(URL.init(fileURLWithPath:)) ?? appState.modifiedWallpaperPath {
            try? FileManager.default.removeItem(at: modifiedWallpaper)
        }

        appState.modifiedWallpaperPath = nil
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}
