//
//  ShadowView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import QuartzCore

final class ShadowView: NSView {

    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        
        gradient.colors = (0...60).map { i in
            let t = Double(i) / 60
            let eased = t * t * (3 - 2 * t)
            return NSColor.black.withAlphaComponent(0.295 * (1 - eased)).cgColor
        }
        
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        
        gradient.type = .axial
        
        return gradient
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
    }
}
