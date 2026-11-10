import Foundation

func errorMessage(for status: OSStatus) -> String {
    switch status {
    case errSecSuccess:
        return "Operation successfully completed."
    case errSecItemNotFound:
        return "Item not found."
    case errSecInteractionNotAllowed:
        return "Device locked. Item unavailable."
    case errSecAuthFailed:
        return "Authentication/Authorization failed."
    case errSecParam:
        return "One or more parameters passed to the function were not valid."
    case errSecDuplicateItem:
        return "The item already exists."
    case -34018:
        return "Entitlement not found. Please refer README."
    case -1:
        return "Error in SecAccessControl!"
    default:
        return "Unhandled Error: Please contact developer to report this error. Error code: \(status)"
    }
}

func decodeAccessConstraints(value: Any) -> [String] {
    if let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() {
        return boolean.boolValue ? [] : ["Denied"]
    }
    guard let constraints = value as? Dictionary<String, Any> else {
        return ["Unknown constraint"]
    }
    var decoded = [String]()
    for key in constraints.keys.sorted() {
        switch key {
        case "cpo": decoded.append("UserPresence")
        case "cup": decoded.append("DevicePasscode")
        case "pkofn":
            if let count = constraints[key] as? NSNumber,
               CFGetTypeID(count) != CFBooleanGetTypeID(), count.doubleValue.isFinite,
               count.doubleValue > 0, count.doubleValue.rounded(.towardZero) == count.doubleValue {
                decoded.append(count.doubleValue == 1 ? "Or" : "And")
            } else {
                decoded.append("Unknown constraint")
            }
        case "cbio":
            if let biometric = constraints[key] as? Dictionary<String, Any> {
                if biometric.count == 1 {
                    decoded.append("BiometryAny")
                } else if biometric.count == 2 {
                    decoded.append("BiometryCurrentSet")
                } else {
                    decoded.append("Biometry (unknown constraint)")
                }
            } else {
                decoded.append("Biometry (unknown constraint)")
            }
        default: decoded.append("Unknown constraint")
        }
    }
    return decoded
}

func decodeAccessOperations(operations: Dictionary<String, Any>, requiresPassword: Bool = false) -> String {
    var decoded = [String]()
    for operation in operations.keys.sorted() {
        guard let value = operations[operation] else { continue }
        switch operation {
        case "dacl": decoded.append("Default ACL")
        case "od": decoded.append(contentsOf: decodeAccessConstraints(value: value))
        case "osgn":
            decoded.append("PrivateKeyUsage")
            decoded.append(contentsOf: decodeAccessConstraints(value: value))
        case "prp": decoded.append("ApplicationPassword")
        default: decoded.append("Unknown operation")
        }
    }
    if requiresPassword && !decoded.contains("ApplicationPassword") {
        decoded.append("ApplicationPassword")
    }
    return decoded.isEmpty ? "No constraints" : decoded.joined(separator: " ")
}

func decodeSecAccessControl(sacObj: Any?) -> String {
    guard let sacObj = sacObj else { return "Not Applicable" }
    let accessControl = sacObj as AnyObject
    // Private API availability is checked by the C wrapper; never read object memory.
    guard accessControlOperationsAvailable() else { return "Unavailable (AccessControl API)" }
    let requiresPassword = accessControlRequiresPassword(accessControl)
    guard let operations = getOperations(accessControl)?.takeUnretainedValue() as? Dictionary<String, Any> else {
        return requiresPassword ? "ApplicationPassword" : "Unavailable (AccessControl constraints)"
    }
    return decodeAccessOperations(operations: operations, requiresPassword: requiresPassword)
}

func determineTypeAndReturnString(value: Any?, accessibility: Bool = false) -> String {
    guard let value = value, !(value is NSNull) else { return "" }
    if let data = value as? Data {
        if let string = String(data: data, encoding: String.Encoding.utf8) { return string }
        return "[Warning] Encoding Shenanigans. Cannot Decode Data. Here is the Hex String: "
            + data.map { String(format: "%02x", $0) }.joined()
    }
    if let date = value as? Date {
        let dateFMT = DateFormatter()
        dateFMT.dateFormat = "MMM dd, yyyy, hh:mm:ss zzz"
        return dateFMT.string(from: date)
    }
    if let string = value as? String {
        guard accessibility else { return string }
        switch string {
        case "ak": return "kSecAttrAccessibleWhenUnlocked"
        case "ck": return "kSecAttrAccessibleAfterFirstUnlock"
        case "dk": return "kSecAttrAccessibleAlways"
        case "aku": return "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"
        case "cku": return "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
        case "dku": return "kSecAttrAccessibleAlwaysThisDeviceOnly"
        case "akpu": return "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly"
        default: return string
        }
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        return number.stringValue
    }
    return String(describing: value)
}

func canonicalizeTypesInReturnedDicts(items: [Dictionary<String, Any>]) -> [Dictionary<String, String>] {

    var dict = Dictionary<String, String>()
    var arrayOfDict = [Dictionary<String, String>]()

    for eachDict in items {
        dict["Account"] = determineTypeAndReturnString(value: eachDict[kSecAttrAccount as String])
        dict["Service"] = determineTypeAndReturnString(value: eachDict[kSecAttrService as String])
        dict["Access Group"] = determineTypeAndReturnString(value: eachDict[kSecAttrAccessGroup as String])
        dict["Creation Time"] = determineTypeAndReturnString(value: eachDict[kSecAttrCreationDate as String])
        dict["Modification Time"] = determineTypeAndReturnString(value: eachDict[kSecAttrModificationDate as String])
        dict["Protection"] = determineTypeAndReturnString(value: eachDict[kSecAttrAccessible as String], accessibility: true)
        dict["Data"] = determineTypeAndReturnString(value: eachDict[kSecValueData as String])
        dict["AccessControl"] = decodeSecAccessControl(sacObj: eachDict[kSecAttrAccessControl as String])

        arrayOfDict.append(dict)
    }

    return arrayOfDict
}

func search(for query: String, in items: [Dictionary<String, String>]) -> [Dictionary<String, String>] {

    var finalItems = [Dictionary<String, String>]()
    let predicateString = "Account CONTAINS[cd] %@ OR Service CONTAINS[cd] %@ OR %K CONTAINS[cd] %@ OR Protection CONTAINS[cd] %@"
    for eachItem in items {
        let predicate = NSPredicate(format: predicateString, query, query, "Access Group", query, query)
        if predicate.evaluate(with: eachItem) {
            finalItems.append(eachItem)
        }
    }
    return finalItems
}

func convertToJSON(for items: [Dictionary<String, String>]) throws -> String {
    let jsonData = try JSONSerialization.data(withJSONObject: items, options: JSONSerialization.WritingOptions.prettyPrinted)
    guard let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else {
        throw NSError(domain: "KeychainEditor.JSON", code: 1, userInfo: nil)
    }
    return jsonString
}

func writeDiagnostic(_ message: String) {
    FileHandle.standardError.write(Data(("KeychainEditor: " + message + "\n").utf8))
}

func writeJSONOutput(_ json: String) throws {
    let written = json.withCString { fputs($0, stdout) >= 0 }
    guard written, fputc(10, stdout) != EOF, fflush(stdout) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}

func outputKeychainDump(result: KeychainDumpResult, filter: String? = nil,
                       output: (String) throws -> Void = { try writeJSONOutput($0) },
                       diagnose: (String) -> Void = { writeDiagnostic($0) }) -> Int32 {
    for message in result.diagnostics { diagnose(message) }
    let items = filter.map { search(for: $0, in: result.items) } ?? result.items
    do {
        try output(try convertToJSON(for: items))
    } catch {
        diagnose("JSON serialization or output failed.")
        return EXIT_FAILURE
    }
    return result.diagnostics.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE
}

func decodeIfBase64(for userData: String) -> String {
    if let decodedData = Data(base64Encoded: userData, options: Data.Base64DecodingOptions.ignoreUnknownCharacters) {
        if let decodedString = String(data: decodedData, encoding: String.Encoding.utf8) {
            return decodedString
        }
    }
    return userData
}
