import Foundation

func printUsage() -> Never {
    print("USAGE: \(CommandLine.arguments[0]) [commands]")
    print("Commands Description")
    print("  -v     version")
    print("  -f     Search. Requires a query string as the second argument.")
    print("  -e     Edit. Requires --account STRING --service STRING [--agroup STRING] --data STRING")
    print("  -d     Delete. Requires --account STRING --service STRING [--agroup STRING]")
    print("  -dg    Delete ALL items in an access group. Requires --agroup STRING --yes. Destructive!")
    print("  -r     Refresh device keychain entitlements and re-sign this tool.")
    print("NOTES:")
    print(" * Account and Service names are used to uniquely identify a item. An optional AccessGroup can also be passed to identify the item.")
    print(" * If there is no Account name pass an empty string.")
    print(" * Search is from the following group {Account, Service, AccessGroup, Protection} and is case in-sensitive.")
    print("EXAMPLES:")
    print(" * To Dump entire keychain: $ keychaineditor")
    print(" * Limit dump by searching: $ keychaineditor -f 'test'")
    print(" * Edit a keychain item:    $ keychaineditor -e --account 'TestAccount' --service 'TestService' --data 'TestData'")
    print(" * Refresh entitlements on-device: $ keychaineditor -r")
    print(" * Refresh then search: $ keychaineditor -r -f 'io.new.app'")
    exit(EXIT_FAILURE)
}

func handleSearch(args: UserDefaults) {
    if let query = args.string(forKey: "f") {
        exit(outputKeychainDump(result: dumpKeychainItems(), filter: query))
    } else {
        printUsage()
    }
}

func handleEdit(args: UserDefaults) {
    if let account = args.string(forKey: "-account") , let service = args.string(forKey: "-service") , let data = args.string(forKey: "-data") {
        let status = updateKeychainItem(account: account, service: service, data: decodeIfBase64(for: data), agroup: args.string(forKey: "-agroup"))
        print(errorMessage(for: status))
    } else {
        printUsage()
    }
}

func handleDelete(args: UserDefaults) {
    if let account = args.string(forKey: "-account") , let service = args.string(forKey: "-service") {
        let status = deleteKeychainItem(account: account, service: service, agroup: args.string(forKey: "-agroup"))
        print(errorMessage(for: status))
    } else {
        printUsage()
    }
}

func handleDeleteGroup(args: UserDefaults) {
    guard let agroup = args.string(forKey: "-agroup") else {
        printUsage()  // exits
    }
    guard args.bool(forKey: "-yes") else {
        // The Foundation argument parser only registers flags with a value
        // (`--yes 1`); a bare `--yes` is invisible, so --yes 1 is the required form.
        FileHandle.standardError.write(Data("Refusing to delete without --yes. Preview first:\n".utf8))
        let preview = dumpKeychainItems()
        let items = preview.items.filter { $0["Access Group"] == agroup }
        if items.isEmpty {
            FileHandle.standardError.write(Data("No visible items in access group '\(agroup)'.\n".utf8))
        } else {
            FileHandle.standardError.write(Data("\(items.count) item(s) in access group '\(agroup)':\n".utf8))
            for item in items {
                FileHandle.standardError.write(Data("  Account: \(item["Account"] ?? "?") | Service: \(item["Service"] ?? "?")\n".utf8))
            }
        }
        for message in preview.diagnostics {
            FileHandle.standardError.write(Data("KeychainEditor: \(message)\n".utf8))
        }
        exit(EXIT_FAILURE)
    }

    let count = countKeychainItemsInGroup(agroup: agroup)
    if count == nil {
        FileHandle.standardError.write(Data("KeychainEditor: Cannot verify access group '\(agroup)' before deletion.\n".utf8))
        exit(EXIT_FAILURE)
    }

    let status = deleteAllKeychainItemsInGroup(agroup: agroup)
    print(errorMessage(for: status))
    if status == errSecSuccess {
        let remaining = countKeychainItemsInGroup(agroup: agroup)
        if remaining == 0 {
            print("Verified: access group '\(agroup)' is now empty.")
        } else {
            FileHandle.standardError.write(Data("KeychainEditor: Warning: \(remaining ?? -1) item(s) remain in '\(agroup)' after deletion.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

func handleRefresh() {
    let status = keychain_refresh_current_executable_and_exec(
        Int32(CommandLine.arguments.count),
        CommandLine.unsafeArgv
    )
    if status != 0 {
        let message = "KeychainEditor: entitlement refresh failed (errno \(status)). Install ldid with 'apt install ldid' and retry."
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(EXIT_FAILURE)
    }
    print("KeychainEditor: entitlements refreshed.")
}

/*
  Start of Program.
*/

guard CommandLine.arguments.count >= 2 else {
    exit(outputKeychainDump(result: dumpKeychainItems()))
}

switch CommandLine.arguments[1] {
case "-r": handleRefresh()
case "-v": print("KeychainEditor Version = 2.3")
case "-f": handleSearch(args: UserDefaults.standard)
case "-e": handleEdit(args: UserDefaults.standard)
case "-d": handleDelete(args: UserDefaults.standard)
case "-dg": handleDeleteGroup(args: UserDefaults.standard)
case "-h": printUsage()
default: printUsage()
}
