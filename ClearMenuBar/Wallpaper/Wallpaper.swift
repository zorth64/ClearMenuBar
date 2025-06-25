//
//  Wallpaper.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import AppKit
import OSLog

public enum Wallpaper {
    public enum Screen {
        case all
        case main
        case index(Int)
        case nsScreens([NSScreen])
        
        fileprivate var nsScreens: [NSScreen] {
            switch self {
            case .all:
                return NSScreen.screens
            case .main:
                guard let mainScreen = NSScreen.main else {
                    return []
                }
                
                return [mainScreen]
            case .index(let index):
                guard let screen = NSScreen.screens[safe: index] else {
                    return []
                }
                
                return [screen]
            case .nsScreens(let nsScreens):
                return nsScreens
            }
        }
    }
    
    public enum Scale: String, CaseIterable {
        case auto
        case fill
        case fit
        case stretch
        case center
    }
    
    public static func getLastWallpaperURL() -> URL? {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "log show --last 2m --style syslog --predicate 'subsystem==\"com.apple.wallpaper\" and category==\"image-cache\" and composedMessage contains \"BEGIN - Image cache lookup - url\"' | tail -n 1 | grep -o 'file:///.*,' | sed -e 's/\\,.*$//'"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let url = URL(string: String(output)) {
                return url
            }
        } else { return nil }
        
        return nil
    }
    
    public static func getLastWallpaperURLFromLogs() -> URL? {
        let store = try! OSLogStore.local()
        let interval = store.position(timeIntervalSinceEnd: -60.0)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@ AND composedMessage CONTAINS %@", "com.apple.wallpaper", "image-cache", "BEGIN - Image cache lookup - url")
        let entries = try! store.getEntries(with: [], at: interval, matching: predicate)
        
        var response: [String] = [""]
        let regex = try! NSRegularExpression(pattern: "url: (file://[^,]+)", options: [])
        
        for e in entries {
            if e.composedMessage.contains("BEGIN - Image cache lookup - url: file") {
                response.append(e.composedMessage)
            }
        }
        
        if let lastEntry = response.last {
            let matches = regex.matches(in: lastEntry, options: [], range: NSRange(location: 0, length: lastEntry.utf16.count))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: lastEntry) {
                    let urlString = String(lastEntry[range])
                    
                    if let url = URL(string: urlString) {
                        return url
                    }
                }
            }
        }
        
        return nil
    }
    
    public static func getCurrentWallpaperURL() -> URL? {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "log show --last 2s --style syslog --predicate 'subsystem==\"com.apple.wallpaper\" and category==\"image-cache\" and composedMessage contains \"BEGIN - Image cache lookup - url\"' | tail -n 1 | grep -o 'file:///.*,' | sed -e 's/\\,.*$//'"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let url = URL(string: String(output)) {
                return url
            }
        } else { return nil }
        
        return nil
    }
    
    public static func getCurrentWallpaperURLFromLogs() -> URL? {
        let store = try! OSLogStore.local()
        let interval = store.position(timeIntervalSinceEnd: -1.55)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@ AND composedMessage CONTAINS %@", "com.apple.wallpaper", "image-cache", "BEGIN - Image cache lookup - url")
        let entries = try! store.getEntries(with: [], at: interval, matching: predicate)
        
        var response: [String] = [""]
        let regex = try! NSRegularExpression(pattern: "url: (file://[^,]+)", options: [])
        
        for e in entries {
            if e.composedMessage.contains("BEGIN - Image cache lookup - url: file") {
                response.append(e.composedMessage)
            }
        }
        
        if let lastEntry = response.last {
            let matches = regex.matches(in: lastEntry, options: [], range: NSRange(location: 0, length: lastEntry.utf16.count))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: lastEntry) {
                    let urlString = String(lastEntry[range])
                    
                    if let url = URL(string: urlString) {
                        return url
                    }
                }
            }
        }
        
        return nil
    }
    
    public static func listenToWallpaperChanges() {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--predicate", "subsystem=='com.apple.wallpaper' and category=='image-cache' and composedMessage contains 'BEGIN - Image cache lookup - url'"]
        
        process.standardOutput = pipe
        process.launch()
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readInBackgroundAndNotify()
        
        NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: fileHandle, queue: nil) { notification in
            if let data = notification.userInfo {
                Swift.print(data)
            }
        }
    }
    
    /**
     Get the current wallpapers.
     */
    public static func get(screen: Screen = .all) -> [URL?] {
        let wallpaperURLs = screen.nsScreens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return wallpaperURLs.map { $0.isDirectory ? getLastWallpaperURL() : $0 }
    }
    
    public static func getCurrent(screen: Screen = .all) -> [URL?] {
        let wallpaperURLs = screen.nsScreens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return wallpaperURLs.map { $0.isDirectory ? getCurrentWallpaperURL() : $0 }
    }
}
