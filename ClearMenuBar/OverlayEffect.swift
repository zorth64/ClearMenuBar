//
//  OverlayEffect.swift
//  Clear Menu Bar
//
//  Created by zorth64 on 15/03/26.
//

import Cocoa

public struct OverlayEffect {
    
    public let tintColor: () -> (NSColor)
    
    public init(_ tintColor: @autoclosure @escaping () -> (NSColor)) {
        self.tintColor = tintColor
    }
    
    public static var clear = OverlayEffect(NSColor.clear)
    
    public static var darkShadow = OverlayEffect(NSColor.black.withAlphaComponent(0.305))
    
    public static var lightShadow = OverlayEffect(NSColor.white.withAlphaComponent(0.4))
}
