/// Keep this anchor with every copy or extracted value of its controlled result.
/// A naked graph does not retain this anchor automatically.
public struct LogicKernelRetention: Sendable {
    private let storage: Storage
    internal init(entries: consuming [UInt64: LogicKernelExternalReservation],
                  backing: (any LogicKernelStorageRetaining)?) {
        storage = Storage(entries: entries, backing: backing)
    }
    private final class Storage: Sendable {
        let entries: [UInt64: LogicKernelExternalReservation]
        // The pinned compiler destroys entries before the separately held backing.
        // All three portability probes verify this order using actual lease events.
        let backing: (any LogicKernelStorageRetaining)?
        init(entries: consuming [UInt64: LogicKernelExternalReservation],
             backing: (any LogicKernelStorageRetaining)?) {
            self.entries = entries
            self.backing = backing
        }
    }
    internal static var metadataBytes: UInt64 {
        UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<[UInt64: LogicKernelExternalReservation]>.stride
               + MemoryLayout<(any LogicKernelStorageRetaining)?>.stride)
    }
}

internal struct LogicKernelExternalReservation: Sendable {
    let byteCount: UInt64
    let lease: any LogicKernelStorageRetaining
}
