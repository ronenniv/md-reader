#!/usr/bin/env swift
// Makes the given app the DEFAULT handler for markdown files, so
// double-clicking a .md in Finder opens it. Run after the app is copied to
// /Applications and registered with LaunchServices (make install does both).
import AppKit
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: set-default-handler.swift /path/to/MDReader.app")
    exit(1)
}
let appURL = URL(fileURLWithPath: arguments[1])
guard FileManager.default.fileExists(atPath: appURL.path) else {
    print("error: \(appURL.path) does not exist")
    exit(1)
}

var types: [UTType] = []
if let markdown = UTType("net.daringfireball.markdown") {
    types.append(markdown)
}
for ext in ["md", "markdown", "mdown", "mkd"] {
    if let type = UTType(filenameExtension: ext), !types.contains(type) {
        types.append(type)
    }
}
guard !types.isEmpty else {
    print("error: could not resolve any markdown UTType — is the app registered with LaunchServices?")
    exit(1)
}

// The API is asynchronous: wait for every completion before exiting.
let group = DispatchGroup()
var failures = 0
for type in types {
    group.enter()
    NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
        if let error {
            print("  \(type.identifier): FAILED — \(error.localizedDescription)")
            failures += 1
        } else {
            print("  \(type.identifier): default handler → \(appURL.lastPathComponent)")
        }
        group.leave()
    }
}

let deadline = Date().addingTimeInterval(15)
while group.wait(timeout: .now()) == .timedOut && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}
if group.wait(timeout: .now()) == .timedOut {
    print("error: timed out waiting for LaunchServices")
    exit(1)
}
exit(failures == 0 ? 0 : 1)
