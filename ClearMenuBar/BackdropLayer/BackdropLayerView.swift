//
//  BackdropLayerView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI
import QuartzCore
import BHSwiftOSLogStream

public class BackdropLayerView: NSVisualEffectView {
    private var gradient: CAGradientLayer? = nil
    private var backdrop: CABackdropLayer? = nil
    private var tint: CALayer? = nil
    private var container: CALayer? = nil
    
    private var wallpaper: CALayer? = nil
    private var currentWallpaperPath: URL?
    
    private var timer: Timer?
    
    private var transitionDuration: CFTimeInterval = 2.0
    
    public struct Effect {
            
        /// The `backgroundColor` is and autoclosure used to dynamically blend with
        /// the layers and contents behind the `BackdropView`.
        public let backgroundColor: () -> (NSColor)
        
        /// The `tintColor` is an autoclosure used to dynamically set the tint color.
        /// This is also the color used when the `BackdropView` is visually inactive.
        public let tintColor: () -> (NSColor)
        
        /// The `tintFilter` can be any object accepted by `CALayer.compositingFilter`.
        public let tintFilter: Any?
        
        /// Create a new `BackdropView.Effect` with the provided parameters.
        public init(_ backgroundColor: @autoclosure @escaping () -> (NSColor),
                    _ tintColor: @autoclosure @escaping () -> (NSColor),
                    _ tintFilter: Any?)
        {
            self.backgroundColor = backgroundColor
            self.tintColor = tintColor
            self.tintFilter = tintFilter
        }
        
        /// A clear effect (only applies blur and saturation); when inactive,
        /// appears transparent. Not suggested for typical use.
        public static var clear = Effect(NSColor.clear,
                                         NSColor.clear,
                                         nil)
    }
    
    public final class BlendGroup {
        
        /// The notification posted upon deinit of a `BlendGroup`.
        fileprivate static let removedNotification = Notification.Name("BackdropView.BlendGroup.deinit")
        
        /// The internal value used for `CABackdropLayer.groupName`.
        fileprivate let value = UUID().uuidString
        
        /// Create a new `BlendGroup`.
        public init() {}
        
        deinit {
            
            // Alert all `BackdropView`s that we're about to be removed.
            // The `BackdropView` will figure out if it needs to update itself.
            NotificationCenter.default.post(name: BlendGroup.removedNotification,
                                            object: nil, userInfo: ["value": self.value])
        }
        
        /// The `global` BlendGroup, if it is desired that all backdrops share
        /// the same blending group through the layer tree (window).
        public static let global = BlendGroup()
        
        /// The default internal value used for `CABackdropLayer.groupName`.
        /// This is to be used if no `BlendGroup` is set on the `BackdropView`.
        fileprivate static func `default`() -> String {
            return UUID().uuidString
        }
    }
    
    public var effect: BackdropLayerView.Effect = .clear {
        didSet {
            self.backdrop?.backgroundColor = self.effect.backgroundColor().cgColor
            self.tint?.backgroundColor = self.effect.tintColor().cgColor
            self.tint?.compositingFilter = self.effect.tintFilter
        }
    }
    
    public var exposureFactor: CGFloat {
        get { return self.wallpaper?.value(forKeyPath: "filters.exposureAdjust.inputEV") as? CGFloat ?? 0 }
        set {
            self.wallpaper?.setValue(newValue, forKeyPath: "filters.exposureAdjust.inputEV")
        }
    }
    
    public weak var blendingGroup: BlendGroup? = nil {
        didSet {
            self.backdrop?.groupName = self.blendingGroup?.value ?? BlendGroup.default()
        }
    }
    
    public override var blendingMode: NSVisualEffectView.BlendingMode {
        get { return self.window?.contentView == self ? .behindWindow : .withinWindow }
        set { }
    }
    
    /// Always `.appearanceBased`; use `effect` instead.
    public override var material: NSVisualEffectView.Material {
        get { return .appearanceBased }
        set { }
    }
    
    public override var state: NSVisualEffectView.State {
        get { return self._state }
        set { self._state = newValue }
    }
    
    private var _state: NSVisualEffectView.State = .active {
        didSet {
            // Don't be called when `commonInit` hasn't finished.
            guard let _ = self.backdrop else { return }
            
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.commonInit()
    }

    private func commonInit() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.masksToBounds = true
        self.layer?.name = "view"
        
        self.wallpaper = CALayer()
        self.wallpaper!.name = "wallpaper"
        
        if let wallpaperPath = getLastWallpaperImagePath() {
            self.currentWallpaperPath = wallpaperPath
            let croppedImage = cropWallpaperBelowMenuBarArea(imagePath: wallpaperPath)
            
            self.wallpaper?.contents = croppedImage
            
            if let vibranceFilter = CIFilter(name: "CIVibrance") {
                vibranceFilter.name = "vibrance"
                self.wallpaper?.filters = [vibranceFilter]
            }
            if let colorControlsFilter = CIFilter(name: "CIColorControls") {
                colorControlsFilter.name = "colorControls"
                self.wallpaper!.filters?.append(colorControlsFilter)
            }
            if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
                exposureFilter.name = "exposureAdjust"
                self.wallpaper!.filters?.append(exposureFilter)
            }
            
            self.wallpaper!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
        }
        
        // Essentially, tell the `NSVisualEffectView` to not do its job:
        super.state = .active
        super.blendingMode = .behindWindow
        super.material = .appearanceBased
        self.setValue(true, forKey: "clear") // internal material
        
        // Set up our backdrop view:
        self.backdrop = CABackdropLayer()
        self.backdrop!.masksToBounds = true
        self.backdrop!.name = "backdrop"
//        self.backdrop!.allowsGroupBlending = true
        self.backdrop!.allowsGroupOpacity = true
        self.backdrop!.allowsEdgeAntialiasing = false
        self.backdrop!.disablesOccludedBackdropBlurs = true
        self.backdrop!.ignoresOffscreenGroups = false
        self.backdrop!.allowsInPlaceFiltering = false
        self.backdrop!.setValue(1, forKey: "scale")
        self.backdrop!.setValue(0.1, forKey: "bleedAmount")
        self.backdrop!.windowServerAware = true
        
        if let brightnessFilter = CAFilter(type: kCAFilterColorBrightness) {
            brightnessFilter.name = "brightness"
            self.backdrop!.filters = [brightnessFilter]
        }
        
        if let contrastFilter = CAFilter(type: kCAFilterColorContrast) {
            contrastFilter.name = "contrast"
            self.backdrop!.filters?.append(contrastFilter)
        }
        
        if let invertFilter = CAFilter.init(type: kCAFilterColorInvert) {
            invertFilter.name = "invert"
            self.backdrop?.filters?.append(invertFilter)
        }
       
        if let hueRotateFilter = CAFilter.init(type: kCAFilterColorHueRotate) {
            hueRotateFilter.name = "hueRotate"
            hueRotateFilter.setValue(3.14, forKey: "inputAngle")
            self.backdrop!.filters?.append(hueRotateFilter)
        }
        
        self.gradient = CAGradientLayer()
        self.gradient?.name = "gradient"
        
        self.tint = CALayer()
        self.tint?.name = "tint"
        self.container = CALayer()
        self.container?.name = "container"
        self.container?.masksToBounds = true
        self.container?.allowsEdgeAntialiasing = true
        self.container?.sublayers = [self.backdrop!, self.tint!, self.wallpaper!]
        
        self.layer?.insertSublayer(self.container!, at: 0)
        
        self._state = .active
        self.blendingMode = .behindWindow
        
        self.effect = .clear
        
        DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            if let path = self.getLastWallpaperImagePath() {
                if self.currentWallpaperPath != path {
                    self.currentWallpaperPath = path
                    let croppedImage = self.cropWallpaperBelowMenuBarArea(imagePath: path)
                    
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(self.transitionDuration)
                    
                    self.wallpaper?.contents = croppedImage
                    
                    CATransaction.commit()
                }
            }
        }
        
        let logStreamDelegate = LogStreamDelegate()
        let logStream = LogStream.init(subsystem: "com.apple.wallpaper", delegate: logStreamDelegate)
        
        NotificationCenter.default.addObserver(self, selector: #selector(wallpaperChanged(_:)), name: .wallpaperChanged, object: nil)
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        let systemAppearance: NSAppearance = NSApplication.shared.effectiveAppearance
        
        exposureFactor = -1.0
        
        self.wallpaper!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
        
        if (systemAppearance.name == NSAppearance.Name.darkAqua) {
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
            self.backdrop!.setValue(-0.063, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.14, forKeyPath: "filters.contrast.inputAmount")
            
        } else {
            self.backdrop!.setValue(true, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(true, forKeyPath: "filters.hueRotate.enabled")
            self.backdrop!.setValue(0.0919, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.166, forKeyPath: "filters.contrast.inputAmount")
        }
    }
    
    @objc func wallpaperChanged(_ notification: NSNotification) {
        if let url = notification.object as? URL {
            updateWallaper(path: url)
        }
    }
    
    func updateWallaper(path: URL) {
        if self.currentWallpaperPath != path {
            self.currentWallpaperPath = path
            let croppedImage = self.cropWallpaperBelowMenuBarArea(imagePath: path)
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(self.transitionDuration)
            
            self.wallpaper?.contents = croppedImage
            
            CATransaction.commit()
        }
    }
    
    func getLastWallpaperImagePath() -> URL? {
        let wallpapers = Wallpaper.get(screen: .main)
        
        return wallpapers.first!
    }
    
    func getCurrentWallpaperImagePath() -> URL? {
        let wallpapers = Wallpaper.getCurrent(screen: .main)
        
        return wallpapers.first!
    }
    
    func cropWallpaperBelowMenuBarArea(imagePath: URL) -> NSImage? {
        guard let wallpaperImage = NSImage(contentsOf: imagePath) else {
            print("Error while obtaining the wallpaper image.")
            return nil
        }
        
        if let screenFrame = NSScreen.main?.frame, let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let screenWidth = screenFrame.width
            let screenHeight = screenFrame.height
            
            let screenProportion = screenWidth / screenHeight
            let wallpaperProportion = CGFloat(wallpaperCGImage.width) / CGFloat(wallpaperCGImage.height)
            
            
            var newWidth = Int(screenWidth)
            var newHeight = Int(screenHeight)
            let resizedCGImage: CGImage?
            let cropRect: CGRect?
            
            if wallpaperProportion >= screenProportion {
                newWidth = Int(screenHeight / CGFloat(wallpaperCGImage.height) * CGFloat(wallpaperCGImage.width))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                let xOffset = (CGFloat(newWidth) - screenWidth) / 2
                cropRect = CGRect(x: Int(xOffset), y: 0, width: Int(screenWidth), height: Int(NSScreen.main!.menuBarHeight))
            } else {
                newHeight = Int(screenWidth / CGFloat(wallpaperCGImage.width) * CGFloat(wallpaperCGImage.height))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                let yOffset = (CGFloat(newHeight) - screenHeight) / 2
                cropRect = CGRect(x: 0, y: Int(yOffset), width: Int(screenWidth), height: Int(NSScreen.main!.menuBarHeight))
            }
            
            if let croppedCGImage = resizedCGImage?.cropping(to: cropRect!) {
                let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: Int(screenWidth), height: Int(screenHeight)))
                return croppedImage
            }
        }
        
        return nil
    }
    
    /// Update sublayer `frame`.
    public override func layout() {
        super.layout()
        self.container!.frame = self.layer?.bounds ?? .zero
        self.backdrop!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.tint!.frame = self.layer?.bounds ?? .zero
        self.wallpaper!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.gradient!.frame = self.layer?.bounds ?? .zero
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = self.window?.backingScaleFactor ?? 1.0
        self.layer?.contentsScale = scale
        self.container!.contentsScale = scale
        self.backdrop!.contentsScale = scale
        self.tint!.contentsScale = scale
    }
    
}

extension CGImage {
    func resize(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue)
        context?.interpolationQuality = .high
        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
