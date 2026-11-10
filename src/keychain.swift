import Security
import Foundation

func addKeychainItem() -> OSStatus {

    let account: String = "Test Account"
    let service: String = "Test Service"
    let accessibleConstant = kSecAttrAccessibleAlways
    let data: Data = "".data(using: String.Encoding.utf8)!

    var status: OSStatus = -1
    var error: Unmanaged<CFError>?

    if let _ = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlocked, .devicePasscode, &error) {

        let query = [
            kSecClass as String         :   kSecClassGenericPassword as String,
            kSecAttrAccount as String   :   account,
            kSecAttrService as String   :   service,
            kSecAttrAccessible as String:   accessibleConstant,
            // Uncomment the following line to add AccessControl. Make sure
            // "acl" is defined above in the if let scope.
            //kSecAttrAccessControl as String :   acl,
            kSecValueData as String     :   data
            ] as [String : Any]

        status = SecItemAdd(query as CFDictionary, nil)
    } else {
        print("[addItem::SecAccessControl] - " + String(describing: error?.takeUnretainedValue()))
    }
    return status
}

struct KeychainDumpResult {
    let items: [Dictionary<String, String>]
    let diagnostics: [String]
}

typealias KeychainQuery = (CFDictionary, inout AnyObject?) -> OSStatus

func normalizeKeychainResult(value: Any?) -> (items: [Dictionary<String, Any>], hadErrors: Bool) {
    guard let value = value else { return ([], true) }
    if let item = value as? Dictionary<String, Any> {
        return ([item], false)
    }
    guard let values = value as? [Any] else { return ([], true) }
    var items = [Dictionary<String, Any>]()
    var hadErrors = false
    for value in values {
        if let item = value as? Dictionary<String, Any> {
            items.append(item)
        } else {
            hadErrors = true
        }
    }
    return (items, hadErrors)
}

func dumpKeychainItems(queryItems: KeychainQuery = { query, result in
    return SecItemCopyMatching(query, &result)
}) -> KeychainDumpResult {
    var finalArrayOfKeychainItems = [Dictionary<String, Any>]()
    var diagnostics = [String]()
    let accessiblityConstants: [CFString] = [kSecAttrAccessibleAfterFirstUnlock,
                                             kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                             kSecAttrAccessibleAlways,
                                             kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                             kSecAttrAccessibleAlwaysThisDeviceOnly,
                                             kSecAttrAccessibleWhenUnlocked,
                                             kSecAttrAccessibleWhenUnlockedThisDeviceOnly]

    for eachConstant in accessiblityConstants {
        let query: [CFString: Any] = [
            kSecClass             :   kSecClassGenericPassword,
            kSecAttrAccessible    :   eachConstant,
            kSecMatchLimit        :   kSecMatchLimitAll,
            kSecReturnAttributes  :   true,
            kSecReturnData        :   true
        ]
        var returnedItems: AnyObject? = nil
        let status = queryItems(query as CFDictionary, &returnedItems)
        let context = "Generic Password / \(determineTypeAndReturnString(value: eachConstant, accessibility: true))"
        if status == errSecSuccess {
            let normalized = normalizeKeychainResult(value: returnedItems)
            finalArrayOfKeychainItems.append(contentsOf: normalized.items)
            if normalized.hadErrors {
                diagnostics.append("\(context): Security API returned success (0) without a valid dictionary result; output may be incomplete.")
            }
        } else if status != errSecItemNotFound {
            diagnostics.append("\(context): OSStatus \(status): \(errorMessage(for: status))")
        }
    }
    return KeychainDumpResult(items: canonicalizeTypesInReturnedDicts(items: finalArrayOfKeychainItems),
                              diagnostics: diagnostics)
}

func updateKeychainItem(at secClass: String = kSecClassGenericPassword as String,
                account: String,
                service: String,
                data: String,
                agroup: String? = nil) -> OSStatus {

    guard let updatedData = data.data(using: String.Encoding.utf8) else {
        NSLog("UpdateKeychainItem() -> Error while unwrapping user-supplied data.")
        exit(EXIT_FAILURE)
    }

    var query = [
        kSecClass as String         :   secClass,
        kSecAttrAccount as String   :   account,
        kSecAttrService as String   :   service
    ]
    if let unwrappedAGroup = agroup {
        query[kSecAttrAccessGroup as String] = unwrappedAGroup
    }

    let dataToUpdate = [kSecValueData as String : updatedData]
    let status: OSStatus = SecItemUpdate(query as CFDictionary, dataToUpdate as CFDictionary)
    return status
}

func deleteKeychainItem(at secClass: String = kSecClassGenericPassword as String,
                account: String,
                service: String,
                agroup: String? = nil) -> OSStatus {

    var query = [
        kSecClass as String         :   secClass,
        kSecAttrAccount as String   :   account,
        kSecAttrService as String   :   service
    ]
    if let unwrappedAGroup = agroup {
        query[kSecAttrAccessGroup as String] = unwrappedAGroup
    }

    let status: OSStatus = SecItemDelete(query as CFDictionary)
    return status
}

func countKeychainItemsInGroup(agroup: String) -> Int? {
    let query: [CFString: Any] = [
        kSecClass             :   kSecClassGenericPassword,
        kSecAttrAccessGroup   :   agroup as CFString,
        kSecMatchLimit        :   kSecMatchLimitAll,
        kSecReturnAttributes  :   true
    ]
    var result: AnyObject? = nil
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return 0 }
    guard status == errSecSuccess else { return nil }
    if let items = result as? [Any] { return items.count }
    if result is Dictionary<String, Any> { return 1 }
    return nil
}

func deleteAllKeychainItemsInGroup(agroup: String) -> OSStatus {
    // SecItemDelete rejects kSecMatchLimit; match limit only applies to copy queries.
    let query: [CFString: Any] = [
        kSecClass             :   kSecClassGenericPassword,
        kSecAttrAccessGroup   :   agroup as CFString
    ]
    return SecItemDelete(query as CFDictionary)
}
