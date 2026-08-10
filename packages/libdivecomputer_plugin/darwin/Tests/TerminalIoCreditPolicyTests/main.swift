import Foundation

// Standalone test runner for TerminalIoCreditPolicy (no XCTest: the
// LibDCDarwin package cannot build under SwiftPM because it depends on Flutter
// modules only present in the CocoaPods build). Run via run_native_tests.sh.

var failures = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("PASS: \(message)")
    } else {
        print("FAIL: \(message) (main.swift:\(line))")
        failures += 1
    }
}

/// Feed `count` packets through the policy, committing every refill the way a
/// transport whose writes all succeed would. Returns the grants requested.
func drain(_ policy: inout TerminalIoCreditPolicy, packets count: Int) -> [UInt8] {
    var grants: [UInt8] = []
    for _ in 0..<count {
        if let grant = policy.packetReceived() {
            grants.append(grant)
            policy.grantAccepted(grant)
        }
    }
    return grants
}

// 1. The opening grant is 254, not 255: 0xFF is a reserved TIO control value.
do {
    expect(TerminalIoCreditPolicy.initialGrant == 254,
           "initial grant is 254 (0xFF is reserved by the TIO protocol)")
}

// 2. A fresh policy has no credits until the opening grant is committed. This
// is what keeps the transport from believing the bridge is open before the
// initial write to UART Credits RX has actually gone out.
do {
    var policy = TerminalIoCreditPolicy()
    expect(policy.credits == 0, "fresh policy starts at zero credits")
    policy.grantAccepted(TerminalIoCreditPolicy.initialGrant)
    expect(policy.credits == 254, "opening grant credits the balance")
}

// 3. Packets below the threshold cost a credit but ask for nothing.
do {
    var policy = TerminalIoCreditPolicy()
    policy.grantAccepted(TerminalIoCreditPolicy.initialGrant)
    let grants = drain(&policy, packets: 100)
    expect(grants.isEmpty, "no refill requested while the balance is healthy")
    expect(policy.credits == 154, "each packet spends exactly one credit")
}

// 4. The refill fires at the threshold and restores the full balance, so a
// long transfer never runs the module dry. 254 - 32 = 222 credits are granted
// when 32 remain.
do {
    var policy = TerminalIoCreditPolicy()
    policy.grantAccepted(TerminalIoCreditPolicy.initialGrant)
    let grants = drain(&policy, packets: 222)
    expect(grants == [222], "one refill of 222 requested on reaching the threshold")
    expect(policy.credits == 254, "refill restores the full balance")
}

// 5. Regression for the real failure mode: an OSTC logbook dump is thousands
// of notifications. A one-shot grant would stall after 254; the policy must
// keep topping up and never let the balance reach zero.
do {
    var policy = TerminalIoCreditPolicy()
    policy.grantAccepted(TerminalIoCreditPolicy.initialGrant)
    var minimumSeen = Int.max
    var refills = 0
    for _ in 0..<5000 {
        if let grant = policy.packetReceived() {
            refills += 1
            policy.grantAccepted(grant)
        }
        minimumSeen = min(minimumSeen, policy.credits)
    }
    expect(refills > 20, "long transfer refills repeatedly (got \(refills))")
    expect(minimumSeen > 0, "balance never reaches zero (low-water \(minimumSeen))")
}

// 6. A refill the platform rejected is not committed, and the next packet asks
// again. Android allows one GATT operation in flight, so a top-up issued while
// a command write is pending can be refused; the balance must not drift as if
// the credits had been granted.
do {
    var policy = TerminalIoCreditPolicy()
    policy.grantAccepted(TerminalIoCreditPolicy.initialGrant)
    _ = drain(&policy, packets: 221)
    let first = policy.packetReceived()  // reaches the threshold, not committed
    expect(first == 222, "refill requested at the threshold")
    expect(policy.credits == 32, "a rejected refill leaves the balance untouched")
    let second = policy.packetReceived()
    expect(second == 222, "the next packet asks for the refill again")
    policy.grantAccepted(second ?? 0)
    expect(policy.credits == 253, "the accepted retry credits the balance")
}

// 7. The counter cannot go negative even if more packets arrive than were paid
// for (a stale notification delivered before the opening grant, say), so the
// refill amount always stays a valid UInt8.
do {
    var policy = TerminalIoCreditPolicy()
    let grants = (0..<10).map { _ in policy.packetReceived() }
    expect(grants.allSatisfy { $0 == 222 }, "un-granted packets still request a refill")
    expect(policy.credits == 0, "balance floors at zero rather than going negative")
}

if failures == 0 {
    print("All TerminalIoCreditPolicy tests passed.")
    exit(0)
} else {
    print("\(failures) TerminalIoCreditPolicy test(s) FAILED.")
    exit(1)
}
