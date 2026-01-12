//
//  MenuBarWindowController.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import SwiftUI

class MenuBarWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0,
                                y: NSScreen.main!.frame.height - NSScreen.main!.menuBarHeight,
                                width: NSScreen.main!.frame.width,
                                height: NSScreen.main!.menuBarHeight),
            styleMask: [
            ],
            backing: .buffered, defer: false)
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.hasShadow = false
        
        window.level = NSWindow.Level.statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.backgroundColor = NSColor.clear
        window.alphaValue = 1.0
        window.ignoresMouseEvents = true

        let contentView = ContentView()
            .edgesIgnoringSafeArea(.all)
            .allowsHitTesting(false)

        window.contentView = NSHostingView(rootView: contentView)

        self.init(window: window)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
}
