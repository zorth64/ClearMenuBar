//
//  AppDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    
    @IBOutlet weak var menu: NSMenu?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        checkReduceTransparency()

        let menuBarWindow = MenuBarWindow(
            contentRect: NSRect(x: 0,
                                y: NSScreen.main!.frame.height - NSScreen.main!.menuBarHeight,
                                width: NSScreen.main!.frame.width,
                                height: NSScreen.main!.menuBarHeight),
            styleMask: [
            ],
            backing: .buffered, defer: false)
        
        let menuBarWindowController = MenuBarWindowController(window: menuBarWindow)
        menuBarWindowController.showWindow(self)
        
        let shadowWindow = ShadowWindow(
            contentRect: NSRect(x: 0,
                                y: NSScreen.main!.frame.height - (NSScreen.main!.menuBarHeight + 80),
                                width: NSScreen.main!.frame.width,
                                height: 80),
            styleMask: [
           ],
            backing: .buffered, defer: false
        )
        
        let shadowWindowController = ShadowWindowController(window: shadowWindow)
        shadowWindowController.showWindow(self)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
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

    // MARK: - Reduce Transparency Check

    private func checkReduceTransparency() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            return
        }

        guard !UserDefaults.standard.bool(forKey: "SuppressReduceTransparencyAlert") else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Reduce Transparency Required"
        alert.informativeText = "Clear Menu Bar requires the \"Reduce Transparency\" setting to be enabled for the menu bar effect to display correctly.\n\nEnable it in System Settings → Accessibility → Display."
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Anyway")

        let response = alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "SuppressReduceTransparencyAlert")
        }

        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.accessibility?Visual") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func accessibilityDisplayOptionsChanged(_ notification: Notification) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            checkReduceTransparency()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}
