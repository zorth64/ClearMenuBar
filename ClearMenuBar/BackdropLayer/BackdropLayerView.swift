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
import Darwin

enum SpaceAPI {
    typealias MainConnection = @convention(c) () -> Int32
    typealias GetActiveSpace = @convention(c) (Int32) -> UInt64

    static let functions: (MainConnection, GetActiveSpace)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let spaceSymbol = dlsym(handle, "SLSGetActiveSpace") else {
            return nil
        }

        return (unsafeBitCast(mainSymbol, to: MainConnection.self),
                unsafeBitCast(spaceSymbol, to: GetActiveSpace.self))
    }()

    static var activeSpaceID: UInt64? {
        guard let (mainConnection, getActiveSpace) = functions else { return nil }
        return getActiveSpace(mainConnection())
    }

    static var existingSpaceIDs: Set<UInt64>? {
        typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        guard let (mainConnection, _) = functions,
              let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        let copySpaces = unsafeBitCast(symbol, to: CopySpaces.self)
        guard let displays = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let ids = displays.flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
            .compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
        return ids.isEmpty ? nil : Set(ids)
    }

    static func spacesForWindow(_ windowNumber: Int) -> Set<UInt64>? {
        typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        guard windowNumber > 0, let (mainConnection, _) = functions,
              let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SLSCopySpacesForWindows") else { return nil }
        let copySpaces = unsafeBitCast(symbol, to: CopySpaces.self)
        guard let spaces = copySpaces(mainConnection(), 7, [NSNumber(value: windowNumber)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return Set(spaces.map { $0.uint64Value })
    }
}

public class BackdropLayerView: NSVisualEffectView {
    
    private var appState: AppState = Container.main.resolve(AppState.self)!
    private let assignedSpaceID = SpaceAPI.activeSpaceID
    
    private var gradient: CAGradientLayer? = nil
    private var backdrop: CABackdropLayer? = nil
    private var tint: CALayer? = nil
    private var container: CALayer? = nil
    
    private var wallpaper: CALayer? = nil
    private var wallpaperContainer: CALayer? = nil
    private var edgeCover: CALayer? = nil
    
    private var currentWallpaperPath: URL?
    
    private var timer: Timer?
    
    private var transitionDuration: CFTimeInterval = 2.0
    
    private var screenDidWakeObserver: NSObjectProtocol?
    private var screenUnlockedObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    
    private var disposables = Set<AnyCancellable>()
    
    private var logStreamDelegate: LogStreamDelegate?
    private var logStreamObserver: LogStream?

    private let sourceWallpapersKey = "sourceWallpapersBySpace"
    private let modifiedWallpapersKey = "modifiedWallpapersBySpace"
    
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

        self.edgeCover = CALayer()
        self.edgeCover!.name = "menuBarShadowCover"
        self.edgeCover!.contentsGravity = .resize
        self.edgeCover!.masksToBounds = true
        
        refreshWallpaperContents()

        if let vibranceFilter = CIFilter(name: "CIVibrance") {
            vibranceFilter.name = "vibrance"
            self.wallpaper?.filters = [vibranceFilter]
        }
        if let colorControlsFilter = CIFilter(name: "CIColorControls") {
            colorControlsFilter.name = "colorControls"
            self.wallpaper?.filters?.append(colorControlsFilter)
        }
        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.name = "exposureAdjust"
            self.wallpaper?.filters?.append(exposureFilter)
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
        self.container?.allowsEdgeAntialiasing = true
        self.container?.sublayers = [self.backdrop!, self.wallpaperContainer!, self.edgeCover!]
        
        self.layer?.insertSublayer(self.container!, at: 0)
        
        self._state = .active
        self.blendingMode = .behindWindow
        
        screenDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: OperationQueue.main) { [weak self] _ in
                guard let self else { return }
                guard self.assignedSpaceID == SpaceAPI.activeSpaceID else { return }
                self.refreshWallpaperContents()
            }
        
        screenUnlockedObserver = DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            guard self.assignedSpaceID == SpaceAPI.activeSpaceID else { return }
            self.refreshWallpaperContents()
        }
        
        logStreamDelegate = LogStreamDelegate()
        logStreamObserver = LogStream.init(subsystem: "com.apple.wallpaper", delegate: logStreamDelegate!)
        
        NotificationCenter.default.addObserver(self, selector: #selector(wallpaperChanged(_:)), name: .wallpaperChanged, object: nil)
        
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: OperationQueue.main) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.assignedSpaceID == SpaceAPI.activeSpaceID else { return }
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.0)
                    if self.appState.allowReduceTransparencyToBeDisabled {
                        self.prepareWallpaperForOpaqueSystemMenuBar()
                    } else {
                        self.refreshWallpaperContents()
                    }
                    CATransaction.commit()
                }
            }
        
        bindAllowReduceTransparency()

        if appState.allowReduceTransparencyToBeDisabled {
            prepareWallpaperForOpaqueSystemMenuBar()
        }
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        let systemAppearance: NSAppearance = NSApplication.shared.effectiveAppearance

        if appState.allowReduceTransparencyToBeDisabled {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
            self.effect = .clear
            self.backdrop!.setValue(0.0, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.0, forKeyPath: "filters.contrast.inputAmount")
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
            return
        }

        if (systemAppearance.name == NSAppearance.Name.darkAqua) {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
            self.effect = .darkShadow
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
            self.backdrop!.setValue(-0.063, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.14, forKeyPath: "filters.contrast.inputAmount")
        } else {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterMultiplyBlendMode)
            self.effect = .lightShadow
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
            self.backdrop!.setValue(0.0919, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.166, forKeyPath: "filters.contrast.inputAmount")
        }
    }
    
    @objc func wallpaperChanged(_ notification: NSNotification) {
        guard assignedSpaceID == SpaceAPI.activeSpaceID else { return }

        if let url = notification.object as? URL {
            
            guard url.isFileURL else { return }
            
            if let appDir = appState.appSupportDirectory {
                let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
                let normalizedAppDir = appDir.resolvingSymlinksInPath().standardizedFileURL

                if normalizedURL.path.hasPrefix(normalizedAppDir.path) {
                    return
                }
            }
            
            if (self.currentWallpaperPath?.resolvingSymlinksInPath().path !=
                url.resolvingSymlinksInPath().path) {
                self.currentWallpaperPath = url
            } else {
                return
            }

            self.storeWallpaper(url, key: self.sourceWallpapersKey)

            if (appState.allowReduceTransparencyToBeDisabled) {
                modifyImageAndSetAsWallpaper(path: url)
            }
            
            updateMenuBarBackground(path: url)
        }
    }
    
    func updateMenuBarBackground(path: URL, animated: Bool = true) {
        if let croppedImage = self.cropWallpaperBelowMenuBarArea(imagePath: path),
           let isDirectory = Wallpaper.isWallpaperFromADirectory(screen: .main).first ?? false {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated && isDirectory ? self.transitionDuration : 0.0)
            
            self.setWallpaperContents(croppedImage)
            
            CATransaction.commit()
            
        }
    }
    
    func modifyImageAndSetAsWallpaper(path: URL) {
        if let modifiedWallpaper = self.addBlackRectangleToWallpaperOverMenuBarArea(imagePath: path),
           let modifiedWallpaperPath = Wallpaper.saveWallpaper(modifiedWallpaper) {
            do {
                try Wallpaper.set(modifiedWallpaperPath, screen: .main)
                if let oldURL = storedWallpaper(key: modifiedWallpapersKey) {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                storeWallpaper(modifiedWallpaperPath, key: modifiedWallpapersKey)
                appState.modifiedWallpaperPath = modifiedWallpaperPath
            } catch {
                print("Error while setting wallpaper.")
            }
        }
    }

    private func prepareWallpaperForOpaqueSystemMenuBar() {
        guard let path = sourceWallpaperPathForModification() else {
            return
        }

        updateMenuBarBackground(path: path, animated: false)

        if storedWallpaper(key: modifiedWallpapersKey) == nil {
            modifyImageAndSetAsWallpaper(path: path)
        }
    }

    private func sourceWallpaperPathForModification() -> URL? {
        if let path = storedWallpaper(key: sourceWallpapersKey) {
            return path
        }

        let currentDesktopPath = getCurrentWallpaperImagePath()
        let isManagedWallpaper = currentDesktopPath.map(isInApplicationSupport(_:)) ?? false

        if isManagedWallpaper,
           let path = appState.currentWallpaperPath,
           path.isFileURL,
           !path.isDirectory,
           FileManager.default.isReadableFile(atPath: path.path) {
            storeWallpaper(path, key: sourceWallpapersKey)
            return path
        }

        if let windowID = getCurrentWallpaperWindowID(),
           let image = getWallpaperScreenshot(cgWindowID: windowID, fullScreen: true) {
            let screenSize = NSScreen.main?.frame.size ?? .zero
            let liveWallpaper = NSImage(cgImage: image, size: screenSize)
            if let path = Wallpaper.saveWallpaper(liveWallpaper) {
                storeWallpaper(path, key: sourceWallpapersKey)
                currentWallpaperPath = path
                return path
            }
        }

        return resolvedWallpaperPath()
    }

    private func restoreOriginalWallpaper() {
        guard let path = storedWallpaper(key: sourceWallpapersKey) ?? appState.currentWallpaperPath,
              path.isFileURL,
              !path.isDirectory,
              FileManager.default.isReadableFile(atPath: path.path) else {
            return
        }

        do {
            try Wallpaper.set(path, screen: .main)
        } catch {
            print("Error while restoring wallpaper: \(error)")
        }
    }
    
    func getLastWallpaperImagePath() -> URL? {
        Wallpaper.get(screen: .main).compactMap { $0 }.first
    }
    
    func getCurrentWallpaperImagePath() -> URL? {
        Wallpaper.getCurrent(screen: .main).compactMap { $0 }.first
    }

    private func resolvedWallpaperPath() -> URL? {
        let candidates = [
            storedWallpaper(key: sourceWallpapersKey),
            appState.currentWallpaperPath,
            getCurrentWallpaperImagePath(),
            getLastWallpaperImagePath()
        ]

        guard let path = candidates.compactMap({ $0 }).first(where: {
            $0.isFileURL && !$0.isDirectory && FileManager.default.isReadableFile(atPath: $0.path)
        }) else {
            return nil
        }

        currentWallpaperPath = path
        return path
    }

    private func refreshWallpaperContents() {
        if appState.allowReduceTransparencyToBeDisabled,
           let path = sourceWallpaperPathForModification(),
           path.isFileURL,
           !path.isDirectory,
           FileManager.default.isReadableFile(atPath: path.path),
           let image = cropWallpaperBelowMenuBarArea(imagePath: path) {
            setWallpaperContents(image)
            return
        }

        if let windowID = getCurrentWallpaperWindowID() {
            if let image = getWallpaperScreenshot(cgWindowID: windowID) {
                setWallpaperContents(image)
                return
            }
        }

        if let path = resolvedWallpaperPath(),
           let image = cropWallpaperBelowMenuBarArea(imagePath: path) {
            setWallpaperContents(image)
        }
    }

    private func setWallpaperContents(_ contents: Any?) {
        wallpaper?.contents = contents
        edgeCover?.contents = contents
    }

    private func isInApplicationSupport(_ url: URL) -> Bool {
        guard let appDirectory = appState.appSupportDirectory else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
            .hasPrefix(appDirectory.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    private func storedWallpaper(key: String) -> URL? {
        guard let spaceID = assignedSpaceID,
              let paths = UserDefaults.standard.dictionary(forKey: key) as? [String: String],
              let path = paths[String(spaceID)] else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    private func storeWallpaper(_ url: URL, key: String) {
        guard let spaceID = assignedSpaceID else { return }
        var paths = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        paths[String(spaceID)] = url.path
        UserDefaults.standard.set(paths, forKey: key)
    }
    
    func cropWallpaperBelowMenuBarArea(imagePath: URL) -> NSImage? {
        guard let wallpaperImage = NSImage(contentsOf: imagePath) else {
            print("Error while obtaining the wallpaper image.")
            return nil
        }
        
        if let screenFrame = NSScreen.main?.frame, let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let screenWidth = screenFrame.width
            let screenHeight = screenFrame.height
            let overlayHeight = (NSScreen.main?.menuBarHeight ?? 0) + 1
            
            let screenProportion = screenWidth / screenHeight
            let wallpaperProportion = CGFloat(wallpaperCGImage.width) / CGFloat(wallpaperCGImage.height)
            
            var newWidth = Int(screenWidth)
            var newHeight = Int(screenHeight)
            var resizedCGImage: CGImage?
            let cropRect: CGRect
            var count = 3
            
            if wallpaperProportion >= screenProportion {
                newWidth = Int(screenHeight / CGFloat(wallpaperCGImage.height) * CGFloat(wallpaperCGImage.width))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                while (count > 0 && resizedCGImage == nil) {
                    resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                    count -= 1
                }
                
                let xOffset = (CGFloat(newWidth) - screenWidth) / 2
                cropRect = CGRect(x: Int(xOffset), y: 0, width: Int(screenWidth), height: Int(overlayHeight))
            } else {
                newHeight = Int(screenWidth / CGFloat(wallpaperCGImage.width) * CGFloat(wallpaperCGImage.height))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                while (count > 0 && resizedCGImage == nil) {
                    resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                    count -= 1
                }
                
                let yOffset = (CGFloat(newHeight) - screenHeight) / 2
                cropRect = CGRect(x: 0, y: Int(yOffset), width: Int(screenWidth), height: Int(overlayHeight))
            }
            
            guard let croppedCGImage = resizedCGImage?.cropping(to: cropRect) else {
                return nil
            }

            let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: screenWidth, height: overlayHeight))
            
            return croppedImage
        }
        
        return nil
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
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                let mainScreen = NSScreen.main,
                abs(bounds.width - mainScreen.frame.width) < 1,
                abs(bounds.height - mainScreen.frame.height) < 1
            else {
                continue
            }
            
            return cgWindowID
        }

        return nil
    }
    
    private func getWallpaperScreenshot(cgWindowID: CGWindowID) -> CGImage? {
        getWallpaperScreenshot(cgWindowID: cgWindowID, fullScreen: false)
    }

    private func getWallpaperScreenshot(cgWindowID: CGWindowID, fullScreen: Bool) -> CGImage? {
        guard let mainScreen = NSScreen.main else { return nil }
        let options: CGWindowListOption = [.optionAll, .optionIncludingWindow]
        let displayBounds = CGDisplayBounds(mainScreen.id)
        let captureRect = CGRect(x: displayBounds.minX,
                                 y: displayBounds.minY,
                                 width: displayBounds.width,
                                 height: fullScreen ? displayBounds.height : mainScreen.menuBarHeight + 1)
        guard let image = CGWindowListCreateImage(captureRect, options, cgWindowID, .nominalResolution) else { return nil }
        return image
    }
    
    private func bindAllowReduceTransparency() {
        appState.$allowReduceTransparencyToBeDisabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allow in
                guard let self, self.assignedSpaceID == SpaceAPI.activeSpaceID else { return }
                if allow {
                    self.prepareWallpaperForOpaqueSystemMenuBar()
                } else {
                    self.restoreOriginalWallpaper()
                }
                self.refreshWallpaperContents()
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
        self.wallpaper!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.wallpaperContainer!.frame = self.layer?.bounds ?? .zero
        self.edgeCover!.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: 1)
        self.edgeCover!.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1 / max(self.bounds.height, 1))
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
        self.edgeCover!.contentsScale = scale
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
