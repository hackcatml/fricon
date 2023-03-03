import Foundation
import os
import ArgParser

let fridaplistPath: String = "/Library/LaunchDaemons/re.frida.server.plist"

func isProcessRunning(_ processName: String) -> Bool {
    let output = task(launchPath: "/bin/bash", arguments: "-c", "ps ax | grep '\(processName)' | grep -v grep | wc -l")
    guard output != "0" else {
        return false
    }
    return true
}

func fridaStop() -> Void {
    print("frida-server stopped\n\(task(launchPath: "/bin/bash", arguments: "-c", "launchctl unload /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null"))")
    // if still frida-server is running. kill it
    while isProcessRunning("frida-server") {
        let pid = task(launchPath: "/bin/bash", arguments: "-c", "ps ax | grep 'frida-server' | grep -v grep | cut -d' ' -f 2")
        print("\(task(launchPath: "/bin/bash", arguments: "-c", "kill -9 \(pid)"))\n")
    }
}

func checkWeirdFridaProcess(withArgs: Bool, op1: String?, op2: String?) -> Void {
    if isProcessRunning("xpcproxy re.frida.server") {
        print("weird xpcproxy re.frida.server process. restart...\n")
        fridaStop()
                
        // start frida-server again as manual
        var pid: pid_t = 0
        var status: Int32 = 0
        var cStrings: [UnsafeMutablePointer<CChar>?] = []
        if let op1 = op1, let op2 = op2, withArgs {
            cStrings.append(strdup("/usr/sbin/frida-server"))
            cStrings.append(strdup(op1))
            cStrings.append(strdup(op2))
            cStrings.append(nil)
        } else {
            cStrings.append(strdup("/usr/sbin/frida-server"))
            cStrings.append(nil)
        }
        posix_spawn(&pid, "/usr/sbin/frida-server", nil, nil, &cStrings, nil)
        waitpid(pid, &status, WEXITED)
        print("frida-server is now on\n")
        
        // Free the C strings
        for cString in cStrings {
            free(cString)
        }
    }
}

func installFrida(filePath: String) -> Void {
    print("\(task(launchPath: "/bin/bash", arguments: "-c", "dpkg -i \(filePath) 2>/dev/null"))\n")
    checkWeirdFridaProcess(withArgs: false, op1: nil, op2: nil)
}

func downloadFrida(fridaVersion: String) {
    let downloadURL = "https://github.com/frida/frida/releases/download/\(fridaVersion)/frida_\(fridaVersion)_iphoneos-arm.deb"
    guard let url = URL(string: downloadURL) else {
        print("Error: Invalid URL")
        exit(-1)
    }

    // Check if frida-server file already exists at current directory.
    let currDir = FileManager.default.currentDirectoryPath
    let filePath = "\(currDir)/frida-server-\(fridaVersion)"
    if FileManager.default.fileExists(atPath: filePath) {
        print("frida-server file already exists. Installing...")
        installFrida(filePath: filePath)
        exit(0)
    }

    // Create download task.
    let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
        if let error = error {
            print("Download error: \(error.localizedDescription)")
            exit(-1)
        }
        
        guard let location = location else {
            print("Error: Invalid download location")
            exit(-1)
        }
        
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(atPath: location.path, toPath: filePath)
            print("File download and save success at \(filePath)")
            print("Installing frida...")
            installFrida(filePath: filePath)
            exit(0)
        } catch let error {
            print("File save error: \(error.localizedDescription)")
            exit(-1)
        }
    }
    
    // Start download task.
    task.resume()
    dispatchMain()
}

// check if frida-server is installed
func isFridaInstalled() -> Bool {
    let fileManager = FileManager.default
    let installed: Bool = fileManager.fileExists(atPath: fridaplistPath)
    return installed;
}

func showStat(processName: String) -> Void {
    guard isProcessRunning(processName) != false else {
        print("frida-server is not running\n")
        return
    }
    print("\(task(launchPath: "/bin/bash", arguments: "-c", "ps -ef | grep '\(processName)' | grep -v grep"))\n")
}

func writeFridaPlist(op1: String?, op2: String?) {
    guard let dict = NSMutableDictionary(contentsOfFile: fridaplistPath) else {
        return
    }
    let programArguments = dict["ProgramArguments"] as! NSMutableArray
    programArguments.add(op1 as Any)
    programArguments.add(op2 as Any)
    dict.write(toFile: fridaplistPath, atomically: true)
}

func recoverFridaPlist() {
    let origProgramArguments = "/usr/sbin/frida-server"
    guard let dict = NSMutableDictionary(contentsOfFile: fridaplistPath) else {
        return
    }
    dict.setObject([origProgramArguments], forKey: "ProgramArguments" as NSCopying)
    dict.write(toFile: fridaplistPath, atomically: true)
}

func fridaStart(withArgs: Bool, op1: String?, op2: String?) {
    if withArgs == true {
        writeFridaPlist(op1: op1, op2: op2)
    }
    
    guard isFridaInstalled() else {
        print("frida-server is not installed yet\n")
        return
    }
    
    guard !isProcessRunning("frida-server") else {
        print("frida-server is already running. restarting...\n\n")
        fridaStop()
        print("frida-server is now on\n\(task(launchPath: "/bin/bash", arguments: "-c", "launchctl load /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null"))")
        checkWeirdFridaProcess(withArgs: withArgs, op1: op1, op2: op2)
        return
    }
    print("frida-server is now on\n\(task(launchPath: "/bin/bash", arguments: "-c", "launchctl load /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null"))")
    checkWeirdFridaProcess(withArgs: withArgs, op1: op1, op2: op2)
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
                    guard cmdParser.found("version") else {
                        let fridaVersion = task(launchPath: "/bin/bash", arguments: "-c", "curl -sLI https://github.com/frida/frida/releases/latest | grep location: | cut -d ' ' -f 2 | cut -d '/' -f 8")
                        print("latest frida version: \(fridaVersion)")
                        downloadFrida(fridaVersion: fridaVersion)
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
                    print("frida-server version: \(task(launchPath: "/bin/bash", arguments: "-c", "frida-server --version"))\n")
                })
            )
            .command("remove", ArgParser()
                .callback({ String, ArgParser in
                    guard isFridaInstalled() else {
                        print("frida-server is not installed yet\n")
                        return
                    }
                    print("\(task(launchPath: "/bin/bash", arguments: "-c", "dpkg --purge re.frida.server"))\n")
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
