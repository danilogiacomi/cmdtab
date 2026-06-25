import AppKit
import CoreGraphics
import CmdTabCore

enum HotkeyError: Error { case tapCreationFailed }

final class CGEventTapHotkeyMonitor: HotkeyMonitoring {
    var onCommand: ((SwitcherCommand) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startRunLoop: CFRunLoop?
    private var commandDown = false
    private var active = false   // overlay currently showing

    // Key codes (US layout, layout-independent virtual codes).
    private let kTab: Int64 = 48
    private let kEsc: Int64 = 53
    private let kLeft: Int64 = 123, kRight: Int64 = 124, kDown: Int64 = 125, kUp: Int64 = 126

    func start() throws {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<CGEventTapHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw HotkeyError.tapCreationFailed }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        let runLoop = CFRunLoopGetCurrent()
        startRunLoop = runLoop
        CFRunLoopAddSource(runLoop, src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Called when the overlay is dismissed by a path that bypasses this
    /// monitor (e.g. a mouse click on a row commits via the controller). Without
    /// this, our `active` mirror stays stuck true while the overlay is actually
    /// closed, so the next ⌘-held Tab is treated as "advance" (ignored) instead
    /// of "open", and Esc/arrows get wrongly swallowed — until ⌘ is released.
    func overlayDidHide() {
        active = false
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = startRunLoop, let src = runLoopSource {
            CFRunLoopRemoveSource(runLoop, src, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        startRunLoop = nil
        active = false
        commandDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Self-heal: the system disables taps on timeout / overload.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        if type == .flagsChanged {
            let nowDown = flags.contains(.maskCommand)
            if commandDown && !nowDown {
                commandDown = false
                if active {
                    active = false
                    emit(.commit)
                    return nil   // swallow the flags change that ends the gesture
                }
            } else {
                commandDown = nowDown
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, commandDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let shift = flags.contains(.maskShift)
            switch keyCode {
            case kTab:
                if active {
                    emit(shift ? .previous : .next)
                } else {
                    active = true
                    emit(.show)
                    if shift { emit(.previous) }
                }
                return nil
            case kEsc where active:
                active = false
                emit(.cancel)
                return nil
            case kLeft where active:  emit(.moveLeft);  return nil
            case kRight where active: emit(.moveRight); return nil
            case kDown where active:  emit(.moveDown);  return nil
            case kUp where active:    emit(.moveUp);    return nil
            default:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func emit(_ command: SwitcherCommand) {
        let handler = onCommand
        DispatchQueue.main.async { handler?(command) }
    }
}
