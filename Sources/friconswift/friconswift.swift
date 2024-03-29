import Foundation
import os
import ArgParser
import cdaswift

let fridaplistPath: String = "/Library/LaunchDaemons/re.frida.server.plist"
let fridaserverPath: String = "/usr/sbin/frida-server"
let bashPath: String = "/bin/bash"
let rootlessPrefix: String = "/var/jb"

var fridaVersion: String?
let dispatchGroup = DispatchGroup()

let isDopamine: Bool = AppUtils.sharedInstance().searchAppExecutable("com.opa334.Dopamine") != "Nope" ? true : false
let fridaVersionForDopamine: [String] = (11...19).map { "16.0.\($0)" } + (0...4).map { "16.1.\($0)" }

// Check if it's rootless
func isRootless() -> Bool {
    let rootlessPath = "/var/jb/usr/bin/su"
    if access(rootlessPath, F_OK) == 0 {
        return true
    }
    return false
}

func rootlessPath(path: String) -> String {
    var path = path
    if isRootless() {
        path = rootlessPrefix + path
    }
    return path
}

func isProcessRunning(_ processName: String) -> Bool {
    let output = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "ps ax | grep '\(processName)' | grep -v grep | wc -l")
    guard output != "0" else {
        return false
    }
    return true
}

func fridaStop() -> Void {
    let argument: String = "launchctl unload " + rootlessPath(path: fridaplistPath) + " 2>/dev/null"
    let _ = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", argument)
    print("frida-server stopped\n")
    // if still frida-server is running. kill it
    while isProcessRunning("frida-server") {
        let pid = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "ps ax | grep 'frida-server' | grep -v grep | tr -s ' ' | cut -d' ' -f 2")
        let _ = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "kill -9 \(pid)")
    }
}

func checkWeirdFridaProcess(withArgs: Bool, op1: String?, op2: String?) -> Void {
    if isProcessRunning("xpcproxy re.frida.server") {
        print("[!] weird xpcproxy re.frida.server process. restart...\n")
        fridaStop()
                
        // start frida-server again as manual
        var pid: pid_t = 0
        var status: Int32 = 0
        var cStrings: [UnsafeMutablePointer<CChar>?] = []
        let fridaServerPath = rootlessPath(path: fridaserverPath)
        if let op1 = op1, let op2 = op2, withArgs {
            cStrings.append(strdup(fridaServerPath))
            cStrings.append(strdup(op1))
            cStrings.append(strdup(op2))
            cStrings.append(nil)
        } else {
            cStrings.append(strdup(fridaServerPath))
            cStrings.append(nil)
        }
        posix_spawn(&pid, fridaServerPath, nil, nil, &cStrings, nil)
        waitpid(pid, &status, WEXITED)
        print("frida-server is now on\n")
        
        // Free the C strings
        for cString in cStrings {
            free(cString)
        }
    }
}

func installFrida(filePath: String) -> Void {
    print("\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "dpkg -i \(filePath) 2>/dev/null"))\n")
    checkWeirdFridaProcess(withArgs: false, op1: nil, op2: nil)
    if !isRootless(), ProcessInfo().operatingSystemVersion.majorVersion >= 16 {
        do {
            // On iOS 16+ rootful? if not patch frida's plist, launchctl load is not working
            let patchTargets: URL = URL(fileURLWithPath: "/Library/LaunchDaemons/re.frida.server.plist")
            var content = try String(contentsOfFile: patchTargets.path, encoding: .utf8)
            if content.contains("LimitLoadToSessionType") {
                content = content.replacingOccurrences(of: "LimitLoadToSessionType", with: "")
                content = content.replacingOccurrences(of: "System", with: "")
                try content.write(toFile: patchTargets.path, atomically: false, encoding: .utf8)
            }
        } catch {
            print("[!] Error patching re.frida.server.plist: \(error)")
        }
        fridaStart(withArgs: false, op1: nil, op2: nil)
    }
}

func fridaVersionCompare(_ v1: String, _ v2: String) -> Bool {
    let components1 = v1.split(separator: ".").compactMap { Int($0) }
    let components2 = v2.split(separator: ".").compactMap { Int($0) }

    for (component1, component2) in zip(components1, components2) {
        if component1 >= component2 {
            return true
        } else if component1 < component2 {
            return false
        }
    }

    return components1.count >= components2.count
}

func downloadFrida(fridaVersion: String) {
    var downloadURL = "https://github.com/frida/frida/releases/download/\(fridaVersion)/frida_\(fridaVersion)_iphoneos-arm.deb"
    
    // frida officialy supports rootless jb from 16.1.4
    if isRootless() && fridaVersionCompare(fridaVersion, "16.1.4") {
        downloadURL = "https://github.com/frida/frida/releases/download/\(fridaVersion)/frida_\(fridaVersion)_iphoneos-arm64.deb"
    }
    
    if isDopamine {
        if !fridaVersionForDopamine.contains(fridaVersion) {
            print("\(fridaVersion) is not supported on Dopamine JB. Choose 16.0.11 ~ 16.1.4")
            exit(1)
        }
        print("\n[*] It's Dopamine. Download frida-server from miticollo's Repo(https://miticollo.github.io/repos/my)")
        downloadURL = "https://miticollo.github.io/repos/my/debs/frida/frida_\(fridaVersion)_iphoneos-universal.deb"
    }
    
    guard let url = URL(string: downloadURL) else {
        print("[!] Error: Invalid URL")
        exit(-1)
    }

    // Check if frida-server file already exists at current directory.
    let currDir = FileManager.default.currentDirectoryPath
    let filePath = "\(currDir)/frida-server-\(fridaVersion)"
    if FileManager.default.fileExists(atPath: filePath + (isRootless() ? "-rootless.deb" : ".deb")) {
        print("frida-server file already exists. Installing...")
        installFrida(filePath: filePath + (isRootless() ? "-rootless.deb" : ".deb"))
        exit(0)
    }
    
    // Create download task.
    let downloadTask = URLSession.shared.downloadTask(with: url) { (location, response, error) in
        if let error = error {
            print("[!] Download error: \(error.localizedDescription)")
            exit(-1)
        }
        
        guard let location = location else {
            print("[!] Error: Invalid download location")
            exit(-1)
        }
        
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(atPath: location.path, toPath: filePath + ".deb")
            print("File download and save success at \(filePath).deb\n")
            if isRootless() {
                if isDopamine {
                    let _ = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "cp \(filePath + ".deb") ./frida-server-\(fridaVersion)-rootless.deb")
                } else if !fridaVersionCompare(fridaVersion, "16.1.4") { // rootless && frida < 16.1.4, need to patch frida-server
                    fridaPatch(filePath: filePath + ".deb", version: fridaVersion)
                } else { // rootless && frida >= 16.1.4, don't have to patch frida-server
                    let _ = task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "cp \(filePath + ".deb") ./frida-server-\(fridaVersion)-rootless.deb")
                }
                // Remove non rootless deb
                try fileManager.removeItem(atPath: filePath + ".deb")
            }
            // Patch done. Let's install frida-server
            print("[*] Installing frida...")
            installFrida(filePath: filePath + (isRootless() ? "-rootless.deb" : ".deb"))
            
            // Remove CFNetworkDownload.tmp file
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath(), includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    if fileURL.absoluteString.contains("CFNetworkDownload") {
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            print("[!] Error removing file: \(error)")
                        }
                    }
                }
            } catch {
                print("[!] Error getting contents of temp directory: \(error)")
            }
            exit(0)
        } catch let error {
            print("[!] File save error: \(error.localizedDescription)")
            exit(-1)
        }
    }
    
    // Start download task.
    downloadTask.resume()
    dispatchMain()
}

// check if frida-server is installed
func isFridaInstalled() -> Bool {
    let fileManager = FileManager.default
    let installed: Bool = fileManager.fileExists(atPath: rootlessPath(path: fridaplistPath))
    return installed;
}

func showStat(processName: String) -> Void {
    guard isProcessRunning(processName) != false else {
        print("frida-server is not running\n")
        return
    }
    print("\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "ps -ef | grep '\(processName)' | grep -v grep"))\n")
}

func writeFridaPlist(op1: String?, op2: String?) {
    guard let dict = NSMutableDictionary(contentsOfFile: rootlessPath(path: fridaplistPath)) else {
        return
    }
    let programArguments = dict["ProgramArguments"] as! NSMutableArray
    programArguments.add(op1 as Any)
    programArguments.add(op2 as Any)
    dict.write(toFile: rootlessPath(path: fridaplistPath), atomically: true)
}

func recoverFridaPlist() {
    let origProgramArguments = rootlessPath(path: fridaserverPath)
    guard let dict = NSMutableDictionary(contentsOfFile: rootlessPath(path: fridaplistPath)) else {
        return
    }
    dict.setObject([origProgramArguments], forKey: "ProgramArguments" as NSCopying)
    dict.write(toFile: rootlessPath(path: fridaplistPath), atomically: true)
}

func fridaStart(withArgs: Bool, op1: String?, op2: String?) {
    if withArgs == true {
        writeFridaPlist(op1: op1, op2: op2)
    }
    
    guard isFridaInstalled() else {
        print("frida-server is not installed yet\n")
        return
    }
    
    let argument: String = "launchctl load " + rootlessPath(path: fridaplistPath) + " 2>/dev/null"
    guard !isProcessRunning("frida-server") else {
        print("frida-server is already running. restarting...\n\n")
        fridaStop()
        print("frida-server is now on\n\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", argument))")
        checkWeirdFridaProcess(withArgs: withArgs, op1: op1, op2: op2)
        return
    }
    print("frida-server is now on\n\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", argument))")
    checkWeirdFridaProcess(withArgs: withArgs, op1: op1, op2: op2)
}

class DelegateToHandle302: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let locationString = response.allHeaderFields["Location"] as? String {
            let versionURL = URL(string: locationString)
            fridaVersion = versionURL?.lastPathComponent
        }
        dispatchGroup.leave()
    }
}

func getLatestFridaVersion() -> String? {
    if isDopamine {
        return fridaVersionForDopamine.last
    }
    
    let url = URL(string: "https://github.com/frida/frida/releases/latest")!
    let session = URLSession(configuration: URLSessionConfiguration.default, delegate: DelegateToHandle302(), delegateQueue: nil)

    dispatchGroup.enter()
    let _ = session.dataTask(with: url).resume()

    dispatchGroup.wait()
    return fridaVersion
}

let helpString: String = """
\nUsage: fricon <command> [options]\n
Commnad:
\tstart: Launch Frida Server
\tstop: Kill Frida Server
\tdownload: Download latest frida-server
\tstat: Show frida-server status
\tversion: Show frida-server version
\tremove: Remove frida
\thelp: Show help\n
Options:
\t-l, --listen <ADDRESS:PORT>: Listen on ADDRESS(only with start command) (ex. fricon start --listen 0.0.0.0:27043)
\t-v, --version <version>: Download Specific version of frida-server(only with download command) (ex. fricon download --version 15.0.8)\n
"""

@main
public struct friconswift {
    public static func main() {
        let parser = ArgParser()
            .helptext(helpString)
            .command("help", ArgParser()
                .callback({ String, ArgParser in
                    print(helpString)
                })
            )
            .command("start", ArgParser()
                .callback({ (cmdName: String, cmdParser: ArgParser) in
                    recoverFridaPlist()
                    guard cmdParser.found("listen") else {
                        fridaStart(withArgs: false, op1: nil, op2: nil)
                        return
                    }
                    let op1 = "-l", op2 = cmdParser.value("listen")
                    fridaStart(withArgs: true, op1: op1, op2: op2)
                })
                .option("listen l")
            )
            .command("download", ArgParser()
                .callback({ (_: String, cmdParser: ArgParser) in
                    print("[*] Downloading frida...")
                    guard cmdParser.found("version") else {
                        if let version = getLatestFridaVersion() {
                            print("Latest Frida version: \(version)")
                            downloadFrida(fridaVersion: version)
                        } else {
                            print("Unable to get the latest frida version")
                        }
                        return
                    }
                    let fridaVersion = cmdParser.value("version")!
                    downloadFrida(fridaVersion: fridaVersion)
                })
                .option("version v")
            )
            .command("stop", ArgParser()
                .callback({(cmdName: String, cmdParser: ArgParser) in
                    guard isFridaInstalled() else {
                        print("frida-server is not installed yet\n\n")
                        return
                    }
                    fridaStop()
                })
            )
            .command("stat", ArgParser()
                .callback({(cmdName: String, cmdParser: ArgParser) in
                    guard isFridaInstalled() else {
                        print("frida-server is not installed yet\n");
                        return
                    }
                    showStat(processName: "frida-server")
                })
            )
            .command("version", ArgParser()
                .callback({ (cmdName: String, cmdParser: ArgParser) in
                    guard isFridaInstalled() else {
                        print("frida-server is not installed yet\n\n")
                        return
                    }
                    print("frida-server version: \(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "frida-server --version"))\n")
                })
            )
            .command("remove", ArgParser()
                .callback({ String, ArgParser in
                    guard isFridaInstalled() else {
                        print("frida-server is not installed yet\n")
                        return
                    }
                    print("\(task(launchPath: rootlessPath(path: bashPath), arguments: "-c", "dpkg --purge re.frida.server"))\n")
                    print("frida-server is removed\n")
                })
            )
        // parser program's arguments
        parser.parse()
        if parser.commandParser == nil {
            print("Usage: fricon <command> [options]. see fricon help\n")
        }
    }
}
