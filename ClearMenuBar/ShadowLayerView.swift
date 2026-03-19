//
//  ShadowLayerView.swift
//  Clear Menu Bar
//
//  Created by zorth64 on 15/03/26.
//

import Cocoa

public class ShadowLayerView: NSView {

    private var tint: CALayer? = nil
    
    public var effect: OverlayEffect = .darkShadow {
        didSet {
            self.tint?.backgroundColor = self.effect.tintColor().cgColor
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.commonInit()
    }

    private func commonInit() {
        self.wantsLayer = true
        
        self.tint = CALayer()
        self.tint?.name = "shadowTint"
        
        let gradient = CAGradientLayer()
        gradient.frame = bounds

        gradient.colors = (0...60).map { i in
            let t = Double(i) / 60
            let eased = t * t * (3 - 2 * t)
            return NSColor.black.withAlphaComponent(1.0 * eased).cgColor
        }

        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)

        gradient.type = .axial
        
        self.tint?.mask = gradient
        
        layer?.addSublayer(self.tint!)
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        let systemAppearance: NSAppearance = NSApplication.shared.effectiveAppearance
        
        if (systemAppearance.name == NSAppearance.Name.darkAqua) {
            self.effect = .darkShadow
        } else {
            self.effect = .lightShadow
        }
    }
    
    /// Update sublayer `frame`.
    public override func layout() {
        super.layout()
        self.tint!.frame = self.layer?.bounds ?? .zero
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = self.window?.backingScaleFactor ?? 1.0
        self.layer?.contentsScale = scale
        self.tint!.contentsScale = scale
    }
}
