// MIT License
// Copyright (c) 2023 LinearMouse
// Copyright (c) 2020 Oskar Groth

import AppKit
import Security

public enum AppMover {
    @discardableResult
    public static func moveIfNecessary() -> Bool {
        let fm = FileManager.default
        guard !Bundle.main.isInstalled,
              let applications = preferredInstallDirectory() else { return false }
        let bundleUrl = Bundle.main.bundleURL
        let bundleName = bundleUrl.lastPathComponent
        let destinationUrl = applications.appendingPathComponent(bundleName)
        let needDestAuth = fm.fileExists(atPath: destinationUrl.path) && !fm.isWritableFile(atPath: destinationUrl.path)
        let needAuth = needDestAuth || !fm.isWritableFile(atPath: applications.path)

        // Activate app -- work-around for focus issues related to "scary file from
        // internet" OS dialog.
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        let alert = NSAlert()
        alert.messageText = "Move to Applications folder"
        alert
            .informativeText =
            "\(Bundle.main.localizedName) needs to move to your Applications folder in order to work properly."
        if needAuth {
            alert.informativeText
                .append("You need to authenticate with your administrator password to complete this step.")
        }
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Do Not Move")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }
        if needAuth {
            let result = authorizedInstall(from: bundleUrl, to: destinationUrl)
            guard !result.cancelled else { return moveIfNecessary() }
            guard result.success else {
                NSApplication.shared.terminate(self)
                return false
            }
        } else {
            if fm.fileExists(atPath: destinationUrl.path) {
                if AppMover.isApplicationAtUrlRunning(destinationUrl) {
                    NSWorkspace.shared.open(destinationUrl)
                    return false
                } else {
                    guard (try? fm.trashItem(at: destinationUrl, resultingItemURL: nil)) != nil else {
                        return false
                    }
                }
            }
            guard (try? fm.copyItem(at: bundleUrl, to: destinationUrl)) != nil else {
                return false
            }
        }

        // Trash the original app
        _ = try? fm.removeItem(at: bundleUrl)

        relaunch(at: destinationUrl.path) {
            DispatchQueue.main.async {
                exit(0)
            }
        }

        return true
    }

    static func authorizedInstall(from sourceURL: URL, to destinationURL: URL) -> (cancelled: Bool, success: Bool) {
        guard destinationURL.representsBundle,
              destinationURL.isValid,
              sourceURL.isValid
        else {
            return (false, false)
        }
        return sourceURL.withUnsafeFileSystemRepresentation { sourcePath -> (cancelled: Bool, success: Bool) in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath -> (cancelled: Bool, success: Bool) in
                guard let sourcePath = sourcePath, let destinationPath = destinationPath else { return (false, false) }
                let deleteCommand = "rm -rf '\(String(cString: destinationPath))'"
                let copyCommand = "cp -pR '\(String(cString: sourcePath))' '\(String(cString: destinationPath))'"
                guard let script =
                    NSAppleScript(
                        source: "do shell script \"\(deleteCommand) && \(copyCommand)\" with administrator privileges"
                    )
                else {
                    return (false, false)
                }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                return ((error?[NSAppleScript.errorNumber] as? Int16) == -128, error == nil)
            }
        }
    }

    static func preferredInstallDirectory() -> URL? {
        let fm = FileManager.default
        let dirs = fm.urls(for: .applicationDirectory, in: .allDomainsMask)
        // Find Applications dir with the most apps that isn't system protected
        return dirs.map { $0.resolvingSymlinksInPath() }.filter { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue && url.path != "/System/Applications"
        }.sorted(by: { left, right in
            left.numberOfFilesInDirectory < right.numberOfFilesInDirectory
        }).last
    }

    static func isApplicationAtUrlRunning(_ url: URL) -> Bool {
        let url = url.standardized
        return NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleURL?.standardized == url
        })
    }

    public static func relaunch(at path: String, completionCallback: @escaping () -> Void) {
        let pid = ProcessInfo.processInfo.processIdentifier
        Process.runTask(
            command: "/usr/bin/xattr",
            arguments: ["-d", "-r", "com.apple.quarantine", path],
            completion: { _ in
                let waitForExitScript =
                    "(while /bin/kill -0 \(pid) >&/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"\(path)\") &"
                Process.runTask(command: "/bin/sh", arguments: ["-c", waitForExitScript])
                completionCallback()
            }
        )
    }
}
