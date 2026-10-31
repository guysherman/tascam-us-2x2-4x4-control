//
//  TascamUSControlApp.swift
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    #if DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            for (index, window) in NSApp.windows.enumerated() {
                print("[debug] window \(index): frame=\(window.frame) content=\(String(describing: window.contentView?.frame)) fitting=\(String(describing: window.contentView?.fittingSize))")
            }
            if let path = ProcessInfo.processInfo.environment["TASCAM_SNAPSHOT"],
               let view = NSApp.windows.first?.contentView {
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
                print("[debug] wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                NSApp.terminate(nil)
            }
        }
    }
    #endif
}

@main
struct TascamUSControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("TASCAM US-2x2 / US-4x4 Settings Panel") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
