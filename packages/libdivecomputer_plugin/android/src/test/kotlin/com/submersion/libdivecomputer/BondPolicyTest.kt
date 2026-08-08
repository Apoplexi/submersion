package com.submersion.libdivecomputer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// JVM tests for the vendor-keyed proactive-bond policy behind the Android
// BLE download path (issue #910): Shearwater devices must not be bonded
// proactively because a Submersion-created bond blocks Shearwater Cloud
// until the user unpairs the computer.
class BondPolicyTest {

    @Test
    fun shearwaterIsExemptFromProactiveBonding() {
        assertFalse(BondPolicy.requiresProactiveBond("Shearwater"))
    }

    @Test
    fun shearwaterMatchIsCaseInsensitive() {
        assertFalse(BondPolicy.requiresProactiveBond("shearwater"))
        assertFalse(BondPolicy.requiresProactiveBond("SHEARWATER"))
    }

    @Test
    fun otherVendorsStillRequireProactiveBonding() {
        assertTrue(BondPolicy.requiresProactiveBond("Aqualung"))
        assertTrue(BondPolicy.requiresProactiveBond("Mares"))
        assertTrue(BondPolicy.requiresProactiveBond("Suunto"))
    }

    @Test
    fun unknownOrEmptyVendorDefaultsToBonding() {
        assertTrue(BondPolicy.requiresProactiveBond(""))
        assertTrue(BondPolicy.requiresProactiveBond("NoSuchVendor"))
    }
}
