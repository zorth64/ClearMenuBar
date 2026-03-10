//
//  LogStreamDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import BHSwiftOSLogStream

class LogStreamDelegate: LogStreamDelegateProtocol {
    
    private var isLocked: Bool = false
    private let lockDuration: TimeInterval = 0.25
    
    func newLogEntry(entry: BHSwiftOSLogStream.LogEntry, history: BHSwiftOSLogStream.History<BHSwiftOSLogStream.LogEntry>) {
        
        guard (entry.description.contains("BEGIN - Image cache lookup - url: file")) else { return }
        
        guard (!isLocked) else { return }
        
        let regex = try! NSRegularExpression(pattern: "url: (file://[^,]+)", options: [])
        
        let matches = regex.matches(in: entry.message, options: [], range: NSRange(location: 0, length: entry.message.utf16.count))
            
        for match in matches {
            if let range = Range(match.range(at: 1), in: entry.message) {
                let urlString = String(entry.message[range])
                
                if let url = URL(string: urlString) {
                    isLocked = true
                    
                    NotificationCenter.default.post(name: .wallpaperChanged, object: url)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + lockDuration) {
                        self.isLocked = false
                    }
                }
            }
        }
    }
    
}

extension Notification.Name {
    static let wallpaperChanged = Notification.Name("wallpaperChanged")
}
