//
//  patch.swift
//  
//
//  Created by hackcatml on 2023/06/10.
//

import Foundation

// Create temp path
func randomStringInLength(_ len: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    var ret = ""
    for _ in 0..<len {
        let randomIndex = letters.index(letters.startIndex, offsetBy: Int(arc4random_uniform(UInt32(letters.count))))
        ret += String(letters[randomIndex])
    }
    return ret
}

func dataWithHexString(hex: String) -> Data {
    var hex = hex.replacingOccurrences(of: " ", with: "")
    var data = Data(capacity: hex.count / 2)
    while hex.count > 0 {
        let subIndex = hex.index(hex.startIndex, offsetBy: 2)
        let c = String(hex[..<subIndex])
        hex = String(hex[subIndex...])
        var ch: UInt64 = 0
        Scanner(string: c).scanHexInt64(&ch)
        var char = UInt8(ch)
        data.append(&char, count: 1)
    }
    return data
}

func patch(fileURL: URL) -> Void {
    if fileURL.pathComponents.contains("control") {
        do {
            // Read the file content
            var content = try String(contentsOfFile: fileURL.path, encoding: .utf8)
            
            // Check if the content has the specified string
            if content.contains("iphoneos-arm") {
                // Replace the string
                content = content.replacingOccurrences(of: "iphoneos-arm", with: "iphoneos-arm64")
                
                // Write the updated content back to the file
                try content.write(toFile: fileURL.path, atomically: false, encoding: .utf8)
            }
            print("\(fileURL.lastPathComponent) has been modified successfully.")
        } catch {
            print("Error: \(error)")
        }
    }
    else if fileURL.pathComponents.contains("re.frida.server.plist") {
        do {
            // Read the file content
            var content = try String(contentsOfFile: fileURL.path, encoding: .utf8)
            
            // Check if the content has the specified string
            if content.contains("/usr/sbin/frida-server") {
                // Replace the string
                content = content.replacingOccurrences(of: "/usr/sbin/frida-server", with: "/var/jb/usr/sbin/frida-server")
                // Remove LimitLoadToSessionType key and value
                // If not, frida-server cannot be loaded on rootless jb with this reason: "Service cannot load in requested session"
                content = content.replacingOccurrences(of: "LimitLoadToSessionType", with: "")
                content = content.replacingOccurrences(of: "System", with: "")
                
                // Write the updated content back to the file
                try content.write(toFile: fileURL.path, atomically: false, encoding: .utf8)
            }
            print("\(fileURL.lastPathComponent) has been modified successfully.")
        } catch {
            print("Error: \(error)")
        }
    }
    else if fileURL.pathComponents.contains("frida-server") {
        do {
            // Read file to Data
            var data = try Data(contentsOf: fileURL)

            // /usr/lib/frida/frida-agent.dylib
            let hexToFind = "2f7573722f6c69622f66726964612f66726964612d6167656e742e64796c6962"
            // /var/jb/frida/frida-agent.dylib'\0'
            let hexToReplaceWith = "2f7661722f6a622f66726964612f66726964612d6167656e742e64796c696200"
            let dataToFind = dataWithHexString(hex: hexToFind)
            let dataToReplaceWith = dataWithHexString(hex: hexToReplaceWith)

            // Find and replace all occurrences
            while let range = data.range(of: dataToFind) {
                data.replaceSubrange(range, with: dataToReplaceWith)
            }

            // Write back to file
            try data.write(to: fileURL)
            print("\(fileURL.lastPathComponent) has been modified successfully.")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    else {
        do {
            // Read the file content
            var content = try String(contentsOfFile: fileURL.path, encoding: .utf8)
            
            // Check if the content has the specified string
            if content.contains("/Library/LaunchDaemons/re.frida.server.plist") {
                // Replace the string
                content = content.replacingOccurrences(of: "/Library/LaunchDaemons/re.frida.server.plist", with: "/var/jb/Library/LaunchDaemons/re.frida.server.plist")
                
                // Write the updated content back to the file
                try content.write(toFile: fileURL.path, atomically: false, encoding: .utf8)
            }
            print("\(fileURL.lastPathComponent) has been modified successfully.")
        } catch {
            print("Error: \(error)")
        }
    }
}

func repackage(fileURL: URL, version: String) -> Void {
    print("\n[*] Repackaging patched frida-server...")
    print("\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "dpkg-deb -b \(fileURL.path) ./frida-server-\(version)-rootless.deb"))")
    print("")
}

func fridaPatch(filePath: String, version: String) -> Void {
    let fileMgr = FileManager.default
    let depackagePath = NSTemporaryDirectory().appending("com.hackcatml.fricon.\(randomStringInLength(6))")
    let workPath = NSTemporaryDirectory().appending("com.hackcatml.fricon.\(randomStringInLength(6))")
    let depackageURL = URL(string: depackagePath)
    let workURL = URL(string: workPath)

    do {
        try fileMgr.createDirectory(atPath: depackageURL!.path, withIntermediateDirectories: true, attributes: nil)
        print("[*] Patching frida for rootless...\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "dpkg-deb -R \(filePath) \(depackagePath)"))")
        
        let dirs = [
            ("DEBIAN", "/DEBIAN"),
            ("Library/LaunchDaemons", "/var/jb/Library/LaunchDaemons"),
            ("usr/sbin", "/var/jb/usr/sbin"),
            ("usr/lib/frida", "/var/jb/frida")
        ]
        
        // Create debian package dir for rootless
        for dir in dirs {
            let dirURL = workURL!.appendingPathComponent(dir.1)
            try fileMgr.createDirectory(atPath: dirURL.path, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Copy files from rootful debian package
        for dir in dirs {
            let srcURL = depackageURL!.appendingPathComponent(dir.0)
            let dstURL = URL(fileURLWithPath: workPath.appending(dir.1))
            
            let fileURLs = try fileMgr.contentsOfDirectory(at: srcURL, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                try fileMgr.copyItem(at: fileURL, to: dstURL.appendingPathComponent(fileURL.lastPathComponent))
            }
        }
    }
    catch {
        print("Error: \(error.localizedDescription)")
    }
    
    // Do patch for frida rootless
    let patchTargets: [String] = ["/DEBIAN/extrainst_", "/DEBIAN/prerm", "/DEBIAN/control", "/var/jb/Library/LaunchDaemons/re.frida.server.plist", "/var/jb/usr/sbin/frida-server"]
    
    for target in patchTargets {
        patch(fileURL: URL(fileURLWithPath: workPath.appending(target)))
    }
    
    // Repackage patched frida-server
    repackage(fileURL: URL(fileURLWithPath: workPath), version: version)
    
    // Cleaning...Remove the temp paths
    do {
        try fileMgr.removeItem(atPath: depackagePath)
        try fileMgr.removeItem(atPath: workPath)
    }
    catch {
        print("Error: \(error.localizedDescription)")
    }
}
