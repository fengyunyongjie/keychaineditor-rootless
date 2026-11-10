import Foundation
import Security

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let sample: [String: Any] = [kSecAttrAccount as String: "Synthetic Account",
                            kSecAttrService as String: "Synthetic Service",
                            kSecValueData as String: Data("Synthetic Data".utf8)]
check(normalizeKeychainResult(value: nil).hadErrors, "success without result")
check(normalizeKeychainResult(value: sample).items.count == 1, "single dictionary")
check(normalizeKeychainResult(value: [sample, sample]).items.count == 2, "array of dictionaries")
check(!normalizeKeychainResult(value: [Any]()).hadErrors, "empty array")
let mixed = normalizeKeychainResult(value: [sample, NSNull(), 42] as [Any])
check(mixed.items.count == 1 && mixed.hadErrors, "preserve valid mixed-array entries")
check(normalizeKeychainResult(value: "unexpected").hadErrors, "unexpected result type")

var calls = 0
let empty = dumpKeychainItems(queryItems: { query, result in
    calls += 1
    check(result == nil, "result reset before each query")
    for key in [kSecReturnData, kSecReturnAttributes] {
        let flag = CFDictionaryGetValue(query, Unmanaged.passUnretained(key).toOpaque())
        check(flag != nil, "return flag present")
        if let flag = flag {
            let object = Unmanaged<AnyObject>.fromOpaque(flag).takeUnretainedValue()
            check(CFGetTypeID(object) == CFBooleanGetTypeID(), "return flag is a CFBoolean")
            check((object as? NSNumber)?.boolValue == true, "return flag is true")
        }
    }
    return errSecItemNotFound
})
check(calls == 7 && empty.items.isEmpty && empty.diagnostics.isEmpty, "item-not-found is normal empty output")
let nilResult = dumpKeychainItems(queryItems: { _, _ in return errSecSuccess })
check(nilResult.items.isEmpty && nilResult.diagnostics.count == 7, "nil success is diagnosed, not trapped")

calls = 0
let partial = dumpKeychainItems(queryItems: { _, result in
    check(result == nil, "no stale result reused")
    calls += 1
    if calls == 1 { result = [sample] as NSArray; return errSecSuccess }
    if calls == 2 { return errSecInteractionNotAllowed }
    return errSecItemNotFound
})
check(partial.items.count == 1 && partial.diagnostics.count == 1, "partial failure preserves data")
check(partial.diagnostics[0].contains(String(errSecInteractionNotAllowed)), "numeric OSStatus diagnostic")
check(!partial.diagnostics[0].contains("Synthetic Data"), "diagnostics do not include data")
for status in [errSecAuthFailed, OSStatus(-34018), errSecParam] {
    let failure = dumpKeychainItems(queryItems: { _, _ in return status })
    check(failure.diagnostics.count == 7 && failure.items.isEmpty, "query failure is accumulated")
}

var output = ""
var messages = [String]()
let partialStatus = outputKeychainDump(result: partial, filter: "Synthetic Service",
                                       output: { output = $0 }, diagnose: { messages.append($0) })
check(partialStatus == EXIT_FAILURE && messages.count == 1, "search propagates partial failure")
let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: String]]
check(json?.count == 1, "partial stdout remains valid JSON")
check(outputKeychainDump(result: empty, output: { output = $0 }, diagnose: { _ in }) == EXIT_SUCCESS,
      "normal empty output succeeds")
check((try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [Any])?.isEmpty == true, "empty JSON output")

check(determineTypeAndReturnString(value: nil) == "", "nil field")
check(determineTypeAndReturnString(value: NSNull()) == "", "null field")
check(determineTypeAndReturnString(value: NSNumber(value: 42)) == "42", "numeric field")
check(determineTypeAndReturnString(value: true) == "true", "boolean field")
check(determineTypeAndReturnString(value: Data([0xff])).contains("ff"), "invalid UTF-8 fallback")
check(determineTypeAndReturnString(value: Date(timeIntervalSince1970: 0)).isEmpty == false, "date field")
check(!determineTypeAndReturnString(value: [1, 2]).isEmpty, "array field")
check(!determineTypeAndReturnString(value: ["nested": 1]).isEmpty, "dictionary field")
check(determineTypeAndReturnString(value: "ak") == "ak", "account data not mapped as protection")
check(determineTypeAndReturnString(value: "ak", accessibility: true).contains("WhenUnlocked"), "protection mapping")
check(decodeAccessOperations(operations: ["osgn": true]).contains("PrivateKeyUsage"), "boolean operation")
check(decodeAccessOperations(operations: ["osgn": ["cup": true]]).contains("DevicePasscode"), "signing operation constraints")
check(decodeAccessOperations(operations: ["od": ["pkofn": "bad", "cbio": NSNull()]]).contains("Unknown"), "malformed constraints")
check(decodeAccessOperations(operations: ["dacl": true], requiresPassword: true).contains("ApplicationPassword"), "password not hidden by default ACL")
check(decodeAccessOperations(operations: ["unknown": 1]).contains("Unknown"), "unknown operation")
check(decodeAccessConstraints(value: ["pkofn": 1.5]).contains("Unknown constraint"), "fractional threshold rejected")
check(outputKeychainDump(result: empty, output: { _ in
    throw NSError(domain: "Synthetic.Output", code: 1, userInfo: nil)
}, diagnose: { _ in }) == EXIT_FAILURE, "output failure returns nonzero")
check(decodeSecAccessControl(sacObj: nil) == "Not Applicable", "absent ACL")
check(getOperations("not an ACL" as CFString) == nil, "wrapper rejects unrelated CF object")

let flags: [(String, SecAccessControlCreateFlags, String)] = [
    ("No flags", [], ""),
    ("UserPresence", .userPresence, "UserPresence"),
    ("DevicePasscode", .devicePasscode, "DevicePasscode"),
    ("PrivateKeyUsage", .privateKeyUsage, "PrivateKeyUsage"),
    ("PrivateKeyUsage + DevicePasscode", [.privateKeyUsage, .devicePasscode], "DevicePasscode"),
    ("ApplicationPassword", .applicationPassword, "ApplicationPassword"),
    ("BiometryAny", .biometryAny, "Biometry"),
    ("BiometryCurrentSet", .biometryCurrentSet, "Biometry")
]
for (name, flag, expected) in flags {
    var error: Unmanaged<CFError>?
    guard let acl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlocked, flag, &error) else {
        check(false, "in-memory ACL creation: " + name)
        continue
    }
    let decoded = decodeSecAccessControl(sacObj: acl)
    if CommandLine.arguments.count == 1 { print("\(name): \(decoded)") }
    if accessControlOperationsAvailable() {
        check(!decoded.isEmpty, "ACL decoded or safely unavailable")
        if !expected.isEmpty { check(decoded.contains(expected), "ACL flag " + name) }
    } else {
        check(decoded.contains("Unavailable"), "private API missing safely downgraded")
    }
}

if let scenario = CommandLine.arguments.dropFirst().first {
    let result: KeychainDumpResult
    switch scenario {
    case "nil": result = nilResult
    case "partial": result = partial
    default: result = empty
    }
    exit(outputKeychainDump(result: result, filter: CommandLine.arguments.dropFirst(2).first))
}
print("PASS: \(assertions) compatibility checks. Only synthetic queries and in-memory ACLs were used.")
