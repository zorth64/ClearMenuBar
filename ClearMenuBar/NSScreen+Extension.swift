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
            return 31
        } else {
            if (self.hasNotch) {
                return 37
            } else {
                return 24
            }
        }
    }
}
