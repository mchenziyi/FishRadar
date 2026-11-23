import AppKit
import Carbon

final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((UInt32) -> Void)?
    private let codes: [Character: UInt32] = ["A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6]
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if result == noErr { Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().onAction?(id.id); return noErr }
            return OSStatus(eventNotHandledErr)
        }, 1, &spec, pointer, &handler)
    }
    func configure(_ keys: [String]) -> Bool {
        let values = keys.map { $0.uppercased() }
        guard values.count == 3, Set(values).count == 3, values.allSatisfy({ $0.count == 1 && codes[$0.first!] != nil }) else { return false }
        for ref in refs { UnregisterEventHotKey(ref) }; refs.removeAll()
        for (index, value) in values.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x46525348, id: UInt32(index + 1))
            let status = RegisterEventHotKey(codes[value.first!]!, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { for ref in refs { UnregisterEventHotKey(ref) }; refs.removeAll(); return false }
            refs.append(ref)
        }
        return true
    }
    deinit { for ref in refs { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}
