//
//  NSScreen+Extension.swift
//  Clear Menu Bar
//
//  Created by zorth64 on 29/12/25.
//

import AppKit

extension NSScreen {
    
    var hasNotch: Bool {
        guard #available(macOS 12, *) else {
            return false
        }
        
        return NSScreen.main?.safeAreaInsets.top != 0
    }
	
	var menuBarHeight: CGFloat {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion
        
        if (macOSVersion.majorVersion == 26) {
            return max(visibleMenuBarHeight, 31)
        } else {
            if (self.hasNotch) {
                return max(visibleMenuBarHeight, 37)
            } else {
                return max(visibleMenuBarHeight, 24)
            }
        }
    }
    
    var visibleMenuBarHeight: CGFloat {
        let dockHeight = NSScreen.main!.visibleFrame.origin.y - NSScreen.main!.frame.origin.y
        let menuBarHeight = NSScreen.main!.frame.height - NSScreen.main!.visibleFrame.height - dockHeight - 1
        
        return menuBarHeight
    }
}
