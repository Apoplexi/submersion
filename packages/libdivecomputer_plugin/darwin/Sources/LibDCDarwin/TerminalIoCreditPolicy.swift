import Foundation

/// Credit accounting for the Telit/Stollmann Terminal I/O (TIO) profile used
/// by the Heinrichs Weikamp BlueMod+SR devices (issue #923).
///
/// The module will not send a byte over the UART bridge until the client has
/// granted it credits, and it spends one credit per notification. A single
/// opening grant therefore only covers the first `initialGrant` packets: an
/// OSTC logbook dump is thousands of notifications, so the client has to top
/// the balance up while the transfer runs.
///
/// Kept as a dependency-free value type (Foundation only) so it can be
/// compiled and unit-tested standalone via run_native_tests.sh, the same way
/// PacketReadBuffer and BleCharacteristicSelector are. The Windows, Linux and
/// Android transports carry line-by-line equivalents.
///
/// Deliberate deviations from Subsurface's core/qt-ble.cpp, which is otherwise
/// the reference for this handshake:
///
///  - Subsurface credits its counter when the GATT write is *confirmed* and
///    refills on `hw_credit == MINIMAL`. An exact-equality test cannot recover
///    if a decrement is ever missed, so the refill here triggers on `<=`.
///  - A refill is only committed once the transport reports that the platform
///    accepted the write request. A rejected request (Android permits one GATT
///    operation in flight at a time, so a top-up can collide with a command
///    write) leaves the balance untouched and the next packet asks again --
///    there are `refillThreshold` packets of slack to retry within.
struct TerminalIoCreditPolicy {
    /// Opening grant. 0xFF is reserved by the TIO protocol, so 254 is the
    /// largest value that means "credits" rather than a control code.
    static let initialGrant: UInt8 = 254
    /// Balance at or below which the client tops the module back up.
    static let refillThreshold = 32

    private(set) var credits = 0

    /// Record the opening grant, once the transport has written it.
    mutating func grantAccepted(_ amount: UInt8) {
        credits += Int(amount)
    }

    /// Account for one received packet.
    ///
    /// Returns the number of credits the caller must now write to UART Credits
    /// RX, or nil while the balance is still healthy. The returned grant is not
    /// applied until the caller reports success via `grantAccepted`.
    mutating func packetReceived() -> UInt8? {
        if credits > 0 {
            credits -= 1
        }
        guard credits <= Self.refillThreshold else { return nil }
        return UInt8(Int(Self.initialGrant) - Self.refillThreshold)
    }
}
