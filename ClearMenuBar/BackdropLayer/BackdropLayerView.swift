//
//  BackdropLayerView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI
import QuartzCore
import BHSwiftOSLogStream
import Swinject
import Combine

public class BackdropLayerView: NSVisualEffectView {
    
    private var appState: AppState = Container.main.resolve(AppState.self)!
    
    private var gradient: CAGradientLayer? = nil
    private var backdrop: CABackdropLayer? = nil
    private var tint: CALayer? = nil
    private var container: CALayer? = nil
    
    private var wallpaper: CALayer? = nil
    private var wallpaperContainer: CALayer? = nil
    
    private var currentWallpaperPath: URL?
    
    private var timer: Timer?
    
    private var transitionDuration: CFTimeInterval = 2.0
    
    private var screenDidWakeObserver: NSObjectProtocol?
    private var screenUnlockedObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    
    private var disposables = Set<AnyCancellable>()
    
    private var logStreamDelegate: LogStreamDelegate?
    private var logStreamObserver: LogStream?
    
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
    
    public var effect: OverlayEffect = .clear {
        didSet {
            self.tint?.backgroundColor = self.effect.tintColor().cgColor
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
        
        self.tint = CALayer()
        self.tint?.name = "tint"
        
        self.wallpaperContainer = CALayer()
        self.wallpaperContainer!.name = "wallpaperContainer"
        
        self.wallpaper = CALayer()
        self.wallpaper!.name = "wallpaper"
        
        if appState.allowReduceTransparencyToBeDisabled,
           let wallpaperPath = appState.currentWallpaperPath {
            self.wallpaper?.contents = cropWallpaperBelowMenuBarArea(imagePath: wallpaperPath)
        } else {
            if appState.allowReduceTransparencyToBeDisabled {
                appState.allowReduceTransparencyToBeDisabled = false
            }
            if let windowID = getCurrentWallpaperWindowID() {
                self.wallpaper?.contents = getWallpaperScreenshot(cgWindowID: windowID)
            }
        }
        
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
        
        self.wallpaperContainer?.sublayers = [self.wallpaper!, self.tint!]
        self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
        
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
        
        self.container = CALayer()
        self.container?.name = "container"
        self.container?.masksToBounds = true
        self.container?.allowsEdgeAntialiasing = false
        self.container?.sublayers = [self.backdrop!, self.wallpaperContainer!]
        
        self.layer?.insertSublayer(self.container!, at: 0)
        
        self._state = .active
        self.blendingMode = .behindWindow
        
        screenDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: OperationQueue.main) { _ in
                if (!self.appState.allowReduceTransparencyToBeDisabled) {
                    if let windowID = self.getCurrentWallpaperWindowID() {
                        self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                    }
                }
            }
        
        screenUnlockedObserver = DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            if (!self.appState.allowReduceTransparencyToBeDisabled) {
                if let path = self.getLastWallpaperImagePath() {
                    if self.currentWallpaperPath != path {
                        self.currentWallpaperPath = path
                        if let windowID = self.getCurrentWallpaperWindowID() {
                            self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                        }
                    }
                }
            }
        }
        
        logStreamDelegate = LogStreamDelegate()
        logStreamObserver = LogStream.init(subsystem: "com.apple.wallpaper", delegate: logStreamDelegate!)
        
        NotificationCenter.default.addObserver(self, selector: #selector(wallpaperChanged(_:)), name: .wallpaperChanged, object: nil)
        
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: OperationQueue.main) { _ in
                if (!self.appState.allowReduceTransparencyToBeDisabled) {
                    if let windowID = self.getCurrentWallpaperWindowID() {
                        CATransaction.begin()
                        CATransaction.setAnimationDuration(0.0)
                        
                        self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                        
                        CATransaction.commit()
                    }
                }
            }
        
        bindAllowReduceTransparency()
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        let systemAppearance: NSAppearance = NSApplication.shared.effectiveAppearance
        
        if (systemAppearance.name == NSAppearance.Name.darkAqua) {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
            self.effect = .darkShadow
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
        } else {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterMultiplyBlendMode)
            self.effect = .lightShadow
        }
        
        if (appState.allowReduceTransparencyToBeDisabled) {
            self.backdrop!.setValue(0.0, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.0, forKeyPath: "filters.contrast.inputAmount")
            if (systemAppearance.name != NSAppearance.Name.darkAqua) {
                self.backdrop!.setValue(true, forKeyPath: "filters.invert.enabled")
                self.backdrop!.setValue(true, forKeyPath: "filters.hueRotate.enabled")
            }
        } else {
            if (systemAppearance.name == NSAppearance.Name.darkAqua) {
                self.backdrop!.setValue(-0.063, forKeyPath: "filters.brightness.inputAmount")
                self.backdrop!.setValue(1.14, forKeyPath: "filters.contrast.inputAmount")
            } else {
                self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
                self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
                self.backdrop!.setValue(0.0919, forKeyPath: "filters.brightness.inputAmount")
                self.backdrop!.setValue(1.166, forKeyPath: "filters.contrast.inputAmount")
            }
        }
    }
    
    @objc func wallpaperChanged(_ notification: NSNotification) {
        if let url = notification.object as? URL {
            
            guard url.isFileURL else { return }

            // 忽略程序自己设置的修改版壁纸，防止覆盖原始壁纸路径。
            if let modified = appState.modifiedWallpaperPath {
                let incoming = url.resolvingSymlinksInPath().standardizedFileURL
                let generated = modified.resolvingSymlinksInPath().standardizedFileURL
                if incoming == generated { return }
            }
            
            if let appDir = appState.appSupportDirectory {
                let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
                let normalizedAppDir = appDir.resolvingSymlinksInPath().standardizedFileURL

                if normalizedURL.path.hasPrefix(normalizedAppDir.path) {
                    return
                }
            }
            
            if (self.currentWallpaperPath?.resolvingSymlinksInPath().path !=
                url.resolvingSymlinksInPath().path) {
                self.appState.originalWallpaperPath = url
                self.currentWallpaperPath = url
            } else {
                return
            }
            
            if (appState.allowReduceTransparencyToBeDisabled) {
                modifyImageAndSetAsWallpaper(path: url)
            }
            
            updateMenuBarBackground(path: url)
        }
    }
    
    func updateMenuBarBackground(path: URL) {
        if let croppedImage = self.cropWallpaperBelowMenuBarArea(imagePath: path),
           let isDirectory = Wallpaper.isWallpaperFromADirectory(screen: .main).first ?? false {
            CATransaction.begin()
            CATransaction.setAnimationDuration(isDirectory ? self.transitionDuration : 0.0)
            
            self.wallpaper?.contents = croppedImage
            
            CATransaction.commit()
            
            if (!isDirectory) {
                appState.currentWallpaperPath = path
            }
        }
    }
    
    func modifyImageAndSetAsWallpaper(path: URL) {
        if let modifiedWallpaper = self.addBlackRectangleToWallpaperOverMenuBarArea(imagePath: path),
           let modifiedWallpaperPath = Wallpaper.saveWallpaper(modifiedWallpaper) {
            do {
                try Wallpaper.set(modifiedWallpaperPath, screen: .main)
                if let oldURL = appState.modifiedWallpaperPath {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                appState.modifiedWallpaperPath = modifiedWallpaperPath
            } catch {
                print("Error while setting wallpaper.")
            }
        }
    }
    
    func getLastWallpaperImagePath() -> URL? {
        let wallpapers = Wallpaper.get(screen: .main)
        
        return wallpapers.first ?? nil
    }
    
    func getCurrentWallpaperImagePath() -> URL? {
        let wallpapers = Wallpaper.getCurrent(screen: .main)
        
        return wallpapers.first!
    }
    
    func cropWallpaperBelowMenuBarArea(imagePath: URL) -> NSImage? {
        guard
            let screen = NSScreen.main,
            let wallpaperImage = NSImage(contentsOf: imagePath),
            let wallpaperCGImage = wallpaperImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        else {
            print("Error while obtaining the wallpaper image or screen.")
            return nil
        }

        // NSScreen 使用逻辑点；CGImage 使用物理像素。
        let scale = screen.backingScaleFactor
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height
        let menuBarHeight = screen.menuBarHeight

        let targetWidth = Int((screenWidth * scale).rounded())
        let targetHeight = Int((screenHeight * scale).rounded())
        let targetMenuBarHeight = Int((menuBarHeight * scale).rounded())

        guard
            targetWidth > 0,
            targetHeight > 0,
            targetMenuBarHeight > 0,
            targetMenuBarHeight <= targetHeight,
            wallpaperCGImage.width > 0,
            wallpaperCGImage.height > 0
        else {
            print("Invalid screen or wallpaper dimensions.")
            return nil
        }

        let sourceWidth = CGFloat(wallpaperCGImage.width)
        let sourceHeight = CGFloat(wallpaperCGImage.height)
        let screenRatio = CGFloat(targetWidth) / CGFloat(targetHeight)
        let wallpaperRatio = sourceWidth / sourceHeight

        // 等比缩放至完整覆盖屏幕，所有尺寸均为物理像素。
        let resizedWidth: Int
        let resizedHeight: Int

        if wallpaperRatio >= screenRatio {
            resizedHeight = targetHeight
            resizedWidth = Int(ceil(CGFloat(targetHeight) * wallpaperRatio))
        } else {
            resizedWidth = targetWidth
            resizedHeight = Int(ceil(CGFloat(targetWidth) / wallpaperRatio))
        }

        guard let resizedImage = wallpaperCGImage.resize(
            width: resizedWidth,
            height: resizedHeight
        ) else {
            print("Failed to resize wallpaper.")
            return nil
        }

        // 屏幕内容居中裁切后，取顶部菜单栏对应的区域。
        let xOffset = max(0, (resizedImage.width - targetWidth) / 2)
        let yOffset = max(0, (resizedImage.height - targetHeight) / 2)

        let cropRect = CGRect(
            x: xOffset,
            y: yOffset,
            width: targetWidth,
            height: targetMenuBarHeight
        )

        guard let croppedCGImage = resizedImage.cropping(to: cropRect) else {
            print("Failed to crop wallpaper for menu bar.")
            return nil
        }

        // 像素尺寸是 Retina 的 2 倍；逻辑显示尺寸仍是屏幕点数。
        return NSImage(
            cgImage: croppedCGImage,
            size: NSSize(width: screenWidth, height: menuBarHeight)
        )
    }

    func addBlackRectangleToWallpaperOverMenuBarArea(imagePath: URL) -> NSImage? {
        guard let wallpaperImage = NSImage(contentsOf: imagePath) else {
            print("Error while obtaining the wallpaper image.")
            return nil
        }
        
        guard let screenFrame = NSScreen.main?.frame,
              let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let screenWidth = screenFrame.width
        let screenHeight = screenFrame.height
        
        let screenProportion = screenWidth / screenHeight
        let wallpaperProportion = CGFloat(wallpaperCGImage.width) / CGFloat(wallpaperCGImage.height)
        
        let menuBarHeight = NSScreen.main!.menuBarHeight
        var newWidth = Int(screenWidth)
        var newHeight = Int(screenHeight)
        var resizedCGImage: CGImage?
        var rect: CGRect
        var count = 3
        
        if wallpaperProportion >= screenProportion {
            newWidth = Int(screenHeight / CGFloat(wallpaperCGImage.height) * CGFloat(wallpaperCGImage.width))
            resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
            
            while (count > 0 && resizedCGImage == nil) {
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                count -= 1
            }
            
            let xOffset = (CGFloat(newWidth) - screenWidth) / 2
            
            rect = CGRect(
                x: xOffset,
                y: CGFloat(newHeight) - menuBarHeight,
                width: screenWidth,
                height: NSScreen.main!.menuBarHeight
            )
            
        } else {
            newHeight = Int(screenWidth / CGFloat(wallpaperCGImage.width) * CGFloat(wallpaperCGImage.height))
            resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
            
            while (count > 0 && resizedCGImage == nil) {
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                count -= 1
            }
            
            let yOffset = (CGFloat(newHeight) - screenHeight) / 2
            
            rect = CGRect(
                x: 0,
                y: CGFloat(newHeight) - menuBarHeight - yOffset,
                width: screenWidth,
                height: NSScreen.main!.menuBarHeight
            )
        }
        
        guard let finalImage = resizedCGImage else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: finalImage.width,
            height: finalImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(finalImage, in: CGRect(x: 0, y: 0, width: finalImage.width, height: finalImage.height))
        
        context.setFillColor(NSColor.black.cgColor)
        
        context.fill(rect)
        
        guard let newCGImage = context.makeImage() else { return nil }
        
        return NSImage(cgImage: newCGImage, size: NSSize(width: screenWidth, height: screenHeight))
    }
    
    private func getCurrentWallpaperWindowID() -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        
        for window in windowList {
            guard
                let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID,
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                ownerName == "Dock",
                let windowName = window[kCGWindowName as String] as? String,
                windowName.contains(/^Wallpaper/),
                let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                boundsDict["Width"] ?? 0 == NSScreen.main!.frame.width,
                boundsDict["Height"] ?? 0 == NSScreen.main!.frame.height
            else {
                continue
            }
            
            return cgWindowID
        }

        return nil
    }
    
    private func getWallpaperScreenshot(cgWindowID: CGWindowID) -> CGImage? {
        let options: CGWindowListOption = [.optionAll, .optionIncludingWindow]
        guard let image = CGWindowListCreateImage(CGRect.init(x: 0, y: 0, width: NSScreen.main!.frame.width, height: NSScreen.main!.menuBarHeight), options, cgWindowID, .nominalResolution) else { return nil }
        return image
    }
    
    private func bindAllowReduceTransparency() {
        appState.$allowReduceTransparencyToBeDisabled
            .receive(on: DispatchQueue.main)
            .sink { allow in
                if (allow) {
                    // 开启开关前，先读取 macOS 当前实际壁纸。
                    // 如果当前壁纸不是本程序生成的修改版，就以它作为最新原图。
                    let actualWallpaperPath =
                        (Wallpaper.getCurrent(screen: .main).first ?? nil)
                        ?? (Wallpaper.get(screen: .main).first ?? nil)

                    if let actualPath = actualWallpaperPath {
                        let actualNormalized =
                            actualPath.resolvingSymlinksInPath().standardizedFileURL
                        let modifiedNormalized = self.appState.modifiedWallpaperPath?
                            .resolvingSymlinksInPath().standardizedFileURL

                        if actualNormalized != modifiedNormalized {
                            self.appState.originalWallpaperPath = actualPath
                            self.appState.currentWallpaperPath = actualPath
                            print("已更新原始壁纸路径：\(actualPath.path)")
                        } else {
                            print("当前壁纸为程序生成的修改版，保留已保存的原图路径。")
                        }
                    }

                    guard let wallpaperPath = self.appState.originalWallpaperPath else {
                        self.appState.allowReduceTransparencyToBeDisabled = false
                        return
                    }
                    self.modifyImageAndSetAsWallpaper(path: wallpaperPath)
                } else {
                    // 关闭实验模式时，恢复原始壁纸。
                    if let originalWallpaperPath = self.appState.originalWallpaperPath {
                        do {
                            try Wallpaper.set(originalWallpaperPath, screen: .main)
                            self.appState.currentWallpaperPath = originalWallpaperPath
                            self.updateMenuBarBackground(path: originalWallpaperPath)
                        } catch {
                            print("Failed to restore original wallpaper: \(error)")
                        }
                    } else {
                        print("Cannot restore original wallpaper: original path is unavailable.")
                    }
                }
                self.viewDidChangeEffectiveAppearance()
            }
            .store(in: &disposables)
    }
    
    /// Update sublayer `frame`.
    public override func layout() {
        super.layout()
        self.container!.frame = self.layer?.bounds ?? .zero
        self.backdrop!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.tint!.frame = self.layer?.bounds ?? .zero
        self.wallpaper!.frame = self.layer?.bounds ?? .zero
        self.wallpaperContainer!.frame = self.layer?.bounds ?? .zero
        self.gradient!.frame = self.layer?.bounds ?? .zero
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = self.window?.backingScaleFactor ?? 1.0
        self.layer?.contentsScale = scale
        self.container!.contentsScale = scale
        self.backdrop!.contentsScale = scale
        self.tint!.contentsScale = scale
        self.wallpaper!.contentsScale = scale
        self.wallpaperContainer!.contentsScale = scale
    }
    
    deinit {
        if let observer = screenDidWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            screenDidWakeObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
            screenUnlockedObserver = nil
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .wallpaperChanged, object: nil)
        logStreamObserver = nil
        logStreamDelegate = nil
    }
}

extension CGImage {
    func resize(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let rep = NSBitmapImageRep(cgImage: self)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Failed to create CGContext")
            return nil
        }

        context.interpolationQuality = .high

        context.draw(
            rep.cgImage!,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        return context.makeImage()
    }
}
