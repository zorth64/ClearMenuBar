//
//  MenuBarWindowController.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import SwiftUI

class MenuBarWindow: NSWindow {
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }
    
    func setup() {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        hasShadow = false
        
        level = NSWindow.Level.statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        backgroundColor = NSColor.clear
        alphaValue = 0.0
        ignoresMouseEvents = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 2.0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            self.animator().alphaValue = 1.0
        })
    }
}

class MenuBarWindowController: NSWindowController {
    init(window: MenuBarWindow) {
        super.init(window: window)
        
        let backdropView = BackdropLayerView()
        backdropView.layerUsesCoreImageFilters = true
        backdropView.autoresizingMask = [.width]
        
        window.contentView = backdropView
        
        window.setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
