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
}
