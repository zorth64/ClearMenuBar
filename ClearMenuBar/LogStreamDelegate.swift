//
//  LogStreamDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import BHSwiftOSLogStream

class LogStreamDelegate: LogStreamDelegateProtocol {
    
    func newLogEntry(entry: BHSwiftOSLogStream.LogEntry, history: BHSwiftOSLogStream.History<BHSwiftOSLogStream.LogEntry>) {
        
        if (entry.description.contains("BEGIN - Image cache lookup - url: file")) {
            let regex = try! NSRegularExpression(pattern: "url: (file://[^,]+)", options: [])
            
            let matches = regex.matches(in: entry.message, options: [], range: NSRange(location: 0, length: entry.message.utf16.count))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: entry.message) {
                    let urlString = String(entry.message[range])
                    
                    if let url = URL(string: urlString) {
                        NotificationCenter.default.post(name: .wallpaperChanged, object: url)
                    }
                }
            }
        }
    }
    
}

extension Notification.Name {
    static let wallpaperChanged = Notification.Name("wallpaperChanged")
}
