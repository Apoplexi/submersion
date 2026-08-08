package com.submersion.libdivecomputer

// Decides whether the Android BLE download path should proactively bond
// (BluetoothDevice.createBond) with a dive computer before starting I/O.
//
// Most vendors keep the proactive bond: devices using encrypted BLE
// services (e.g. Aqualung i300C on the Pelagic service) need an
// established bond before the first read. Shearwater's protocol uses no
// encrypted characteristics -- Shearwater Cloud connects without pairing
// -- and a bond created by Submersion blocks Shearwater Cloud from
// connecting until the user unpairs the computer in Android Bluetooth
// settings (issue #910).
//
// Skipping the proactive bond cannot strand a download: if a device does
// demand encryption mid-session, the Android stack pairs transparently
// during the first encrypted GATT operation (see
// BleIoStream.connectAndDiscover).
object BondPolicy {
    private val vendorsWithoutProactiveBond = setOf("shearwater")

    // vendor is the libdivecomputer descriptor vendor string
    // (DiscoveredDevice.vendor), e.g. "Shearwater" for Petrel, Perdix,
    // Teric, Nerd, Peregrine, and Tern models.
    fun requiresProactiveBond(vendor: String): Boolean =
        vendor.trim().lowercase() !in vendorsWithoutProactiveBond
}
