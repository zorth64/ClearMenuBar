//
//  AppState.swift
//  Clear Menu Bar
//
//  Created by zorth64 on 11/03/26.
//

import SwiftUI

class AppState: ObservableObject {
    @Published var allowReduceTransparencyToBeDisabled: Bool = false {
        didSet {
            storedAllowReduceTransparencyToBeDisabled = allowReduceTransparencyToBeDisabled
        }
    }
    @Published var currentWallpaperPath: URL? {
        didSet {
            storedCurrentWallpaperPath = currentWallpaperPath
        }
    }
    @Published var originalWallpaperPath: URL? {
        didSet { storedOriginalWallpaperPath = originalWallpaperPath }
    }
    @Published var modifiedWallpaperPath: URL? {
        didSet {
            storedModifiedWallpaperPath = modifiedWallpaperPath
        }
    }
    
    @AppStorage("allowReduceTransparencyDisabled") private var storedAllowReduceTransparencyToBeDisabled: Bool = false
    @AppStorage("currentWallpaperPath") private var storedCurrentWallpaperPath: URL?
    @AppStorage("originalWallpaperPath") private var storedOriginalWallpaperPath: URL?
    @AppStorage("modifiedWallpaperPath") private var storedModifiedWallpaperPath: URL?
    
    lazy var appSupportDirectory: URL? = {
        return Wallpaper.applicationSupportDirectory()
    }()
    
    init() {
        allowReduceTransparencyToBeDisabled = storedAllowReduceTransparencyToBeDisabled

        let actualWallpaperPath = (Wallpaper.getCurrent(screen: .main).first ?? nil)
            ?? (Wallpaper.get(screen: .main).first ?? nil)

        let modifiedPath = storedModifiedWallpaperPath?
            .resolvingSymlinksInPath().standardizedFileURL

        func isStoredModifiedWallpaper(_ path: URL?) -> Bool {
            guard let path = path else { return false }
            let normalized = path.resolvingSymlinksInPath().standardizedFileURL
            return normalized == modifiedPath
        }

        let initialOriginalPath: URL?
        if let savedOriginal = storedOriginalWallpaperPath,
           !isStoredModifiedWallpaper(savedOriginal) {
            initialOriginalPath = savedOriginal
        } else if let actual = actualWallpaperPath,
                  !isStoredModifiedWallpaper(actual) {
            initialOriginalPath = actual
        } else if let savedCurrent = storedCurrentWallpaperPath,
                  !isStoredModifiedWallpaper(savedCurrent) {
            initialOriginalPath = savedCurrent
        } else {
            initialOriginalPath = nil
        }

        originalWallpaperPath = initialOriginalPath
        currentWallpaperPath = initialOriginalPath
        modifiedWallpaperPath = storedModifiedWallpaperPath
    }
}
