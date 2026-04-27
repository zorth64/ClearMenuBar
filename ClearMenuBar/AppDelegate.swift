//
//  AppDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    
    @IBOutlet weak var menu: NSMenu?
    
    var preferencesWindow: NSWindow?
        
    override init() {
        super.init()
        
        Dependencies.setup()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        
        statusItem?.behavior = .removalAllowed

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

    // If the menu bar item was hidden, and the user reopens the app while it's running, show the menu bar item again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusItem?.isVisible == false {
            statusItem?.isVisible = true
        }
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}
