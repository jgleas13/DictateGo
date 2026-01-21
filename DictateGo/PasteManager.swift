import AppKit
import Carbon
import ApplicationServices

// Compat constants for SDKs that don't expose these AX symbols.
private let kAXSearchFieldRole = "AXSearchField" as CFString
private let kAXEditableAttribute = "AXEditable" as CFString
private let kAXSecureTextFieldRole = "AXSecureTextField"
private let kAXTextFieldRole = "AXTextField"
private let kAXTextAreaRole = "AXTextArea"
private let kAXTextViewRole = "AXTextView"
private let kAXComboBoxRole = "AXComboBox"
private let kAXWebAreaRole = "AXWebArea"
private let kAXSelectedTextRangeAttribute = "AXSelectedTextRange" as CFString
private let kAXRoleDescriptionAttribute = "AXRoleDescription" as CFString
private let kAXSelectedTextAttribute = "AXSelectedText" as CFString

final class PasteManager {
    private let axMessagingTimeout: TimeInterval = 0.3
    private let pasteTimeBudget: TimeInterval = 0.6

    @discardableResult
    func paste(text: String, autoPaste: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if autoPaste {
            guard shouldAttemptPasteWithoutFocus() else { return false }
            sendPasteKeystroke()
            return true
        }
        return false
    }

    private func sendPasteKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        } else {
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    private func shouldAttemptPasteWithoutFocus() -> Bool {
        guard let frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        let blockedBundleIds = Set([
            Bundle.main.bundleIdentifier,
            "com.apple.systemsettings",
            "com.apple.systempreferences",
            "com.apple.SystemPreferences"
        ].compactMap { $0 })
        return !blockedBundleIds.contains(frontmostBundleId)
    }

    private func pasteViaMenu() -> Bool {
        let script = """
        with timeout of 1 second
        if application "System Events" is not running then
            tell application "System Events" to launch
            delay 0.1
        end if
        tell application "System Events"
            tell process (name of first application process whose frontmost is true)
                tell (menu item "Paste" of menu of menu item "Paste" of menu "Edit" of menu bar item "Edit" of menu bar 1)
                    if exists then
                        if enabled then
                            click it
                            return true
                        else
                            return false
                        end if
                    end if
                end tell
                tell (menu item "Paste" of menu "Edit" of menu bar item "Edit" of menu bar 1)
                    if exists then
                        if enabled then
                            click it
                            return true
                        else
                            return false
                        end if
                    else
                        return false
                    end if
                end tell
            end tell
        end tell
        end timeout
        """
        guard let scriptObject = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = scriptObject.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }

    private func insertTextAtCursor(_ text: String) -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        applyAXTimeout(systemWideElement)
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef else { return false }
        let focusedElement = focusedElementRef as! AXUIElement
        applyAXTimeout(focusedElement)
        if axSetAttribute(focusedElement, attribute: kAXSelectedTextAttribute, value: text as CFTypeRef) {
            return true
        }
        if axSetAttribute(focusedElement, attribute: kAXValueAttribute as CFString, value: text as CFTypeRef) {
            return true
        }
        return false
    }

    private func focusedElementIsEditable() -> Bool {
        guard let focusedElement = focusedUIElement() else {
            return false
        }
        applyAXTimeout(focusedElement)
        let role = axCopyStringAttribute(focusedElement, attribute: kAXRoleAttribute as CFString)
        if role == kAXSecureTextFieldRole {
            return false
        }

        if let role {
            let allowedRoles: Set<String> = [
                kAXTextFieldRole,
                kAXTextAreaRole,
                kAXTextViewRole,
                kAXSearchFieldRole as String,
                kAXComboBoxRole,
                kAXWebAreaRole
            ]
            if allowedRoles.contains(role) {
                return true
            }
        }

        if let roleDescription = axCopyStringAttribute(
            focusedElement,
            attribute: kAXRoleDescriptionAttribute
        )?.lowercased(), roleDescription.contains("text") || roleDescription.contains("search") {
            return true
        }

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return true
        }

        if AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextRangeAttribute,
            &settable
        ) == .success, settable.boolValue {
            return true
        }

        if let editableValue = axCopyBoolAttribute(focusedElement, attribute: kAXEditableAttribute) {
            return editableValue
        }

        return false
    }

    private func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        applyAXTimeout(systemWide)
        if let element = focusedUIElement(from: systemWide) {
            return resolveFocusedElement(from: element)
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            applyAXTimeout(appElement)
            if let element = focusedUIElement(from: appElement) {
                return resolveFocusedElement(from: element)
            }
        }
        return nil
    }

    private func focusedUIElement(from element: AXUIElement) -> AXUIElement? {
        applyAXTimeout(element)
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard result == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return focusedValue as! AXUIElement
    }

    private func resolveFocusedElement(from element: AXUIElement) -> AXUIElement {
        var current = element
        for _ in 0..<3 {
            applyAXTimeout(current)
            var focusedValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                current,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue
            )
            guard result == .success,
                  let focusedValue,
                  CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
            else {
                break
            }
            let next = focusedValue as! AXUIElement
            if CFEqual(current, next) {
                break
            }
            current = next
        }
        return current
    }

    private func applyAXTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Float(axMessagingTimeout))
    }

    private func axCopyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func axCopyBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func axSetAttribute(_ element: AXUIElement, attribute: CFString, value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute, value) == .success
    }
}
