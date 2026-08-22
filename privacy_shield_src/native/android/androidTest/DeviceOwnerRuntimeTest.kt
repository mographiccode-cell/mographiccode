package com.privacyshield.privacy_shield

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.VpnService
import android.os.Build
import android.os.UserManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeviceOwnerRuntimeTest {
    private lateinit var target: Context
    private lateinit var testContext: Context
    private lateinit var dpm: DevicePolicyManager
    private lateinit var manager: NativePolicyManager
    private lateinit var admin: ComponentName
    private lateinit var location: LocationManager
    private lateinit var testPackage: String

    @Before
    fun setUp() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        target = instrumentation.targetContext
        testContext = instrumentation.context
        testPackage = testContext.packageName
        dpm = target.getSystemService(DevicePolicyManager::class.java)
        location = target.getSystemService(LocationManager::class.java)
        admin = ComponentName(target, PrivacyAdminReceiver::class.java)
        manager = NativePolicyManager(target)

        assertTrue("Privacy Shield must be Device Owner in runtime CI", manager.isDeviceOwner)
        val requested = testContext.packageManager
            .getPackageInfo(testPackage, android.content.pm.PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toSet()
            ?: emptySet()
        assertTrue(requested.contains(Manifest.permission.CAMERA))
        assertTrue(requested.contains(Manifest.permission.RECORD_AUDIO))
    }

    @After
    fun tearDown() {
        runCatching { target.stopService(Intent(target, NetworkShieldService::class.java)) }
        runCatching {
            if (manager.panicEnabled) manager.setPanic(false)
        }
        for (sensor in listOf("camera", "microphone", "location")) {
            runCatching { manager.revokeNow(testPackage, sensor) }
            runCatching { manager.setBlocked(testPackage, sensor, false) }
        }
    }

    @Test
    fun cameraPolicyRoundTripDeniedThenDefault() {
        manager.setBlocked(testPackage, "camera", true)
        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )
        assertTrue(
            manager.blockedPolicies().any {
                it["packageName"] == testPackage && it["sensor"] == "camera"
            },
        )

        manager.setBlocked(testPackage, "camera", false)
        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )
    }

    @Test
    fun microphonePolicyRoundTripDeniedThenDefault() {
        manager.setBlocked(testPackage, "microphone", true)
        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.RECORD_AUDIO),
        )
        manager.setBlocked(testPackage, "microphone", false)
        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.RECORD_AUDIO),
        )
    }

    @Test
    fun temporaryCameraGrantAutomaticallyRelocks() {
        assertTrue("Device Owner provisioning must permit sensor grants", manager.canGrantSensors)
        manager.setBlocked(testPackage, "camera", true)
        manager.temporaryGrant(testPackage, "camera", 10_000L)

        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )
        assertTrue(manager.activeSessions().isNotEmpty())

        Thread.sleep(13_500L)

        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )
        assertTrue(manager.activeSessions().isEmpty())
    }

    @Test
    fun repairClosesOrphanGrantedSensor() {
        assertTrue(
            dpm.setPermissionGrantState(
                admin,
                testPackage,
                Manifest.permission.CAMERA,
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            ),
        )
        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )

        manager.repairPolicies()

        assertEquals(
            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
            dpm.getPermissionGrantState(admin, testPackage, Manifest.permission.CAMERA),
        )
        assertTrue(
            manager.blockedPolicies().any {
                it["packageName"] == testPackage && it["sensor"] == "camera"
            },
        )
    }

    @Test
    fun panicLockEnforcesAndRestoresGlobalState() {
        val beforeCamera = dpm.getCameraDisabled(admin)
        val beforeRestrictions = dpm.getUserRestrictions(admin)
        val beforeMicRestriction =
            beforeRestrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false)
        val beforeLocationRestriction =
            beforeRestrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false)
        val beforeLocationEnabled = location.isLocationEnabled
        val beforeScreenCapture = dpm.getScreenCaptureDisabled(admin)

        manager.setPanic(true)

        val lockedRestrictions = dpm.getUserRestrictions(admin)
        assertTrue(dpm.getCameraDisabled(admin))
        assertTrue(lockedRestrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false))
        assertTrue(lockedRestrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false))
        assertFalse(location.isLocationEnabled)
        assertTrue(dpm.getScreenCaptureDisabled(admin))
        assertTrue(manager.panicEnabled)
        assertFalse(manager.panicDegraded)

        manager.setPanic(false)

        val restoredRestrictions = dpm.getUserRestrictions(admin)
        assertEquals(beforeCamera, dpm.getCameraDisabled(admin))
        assertEquals(
            beforeMicRestriction,
            restoredRestrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false),
        )
        assertEquals(
            beforeLocationRestriction,
            restoredRestrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false),
        )
        assertEquals(beforeLocationEnabled, location.isLocationEnabled)
        assertEquals(beforeScreenCapture, dpm.getScreenCaptureDisabled(admin))
        assertFalse(manager.panicEnabled)
    }

    @Test
    fun networkShieldStartsAndStopsAsOwnedVpn() {
        assertNull(
            "CI must grant ACTIVATE_VPN AppOp before instrumentation",
            VpnService.prepare(target),
        )
        val intent = Intent(target, NetworkShieldService::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            target.startForegroundService(intent)
        } else {
            target.startService(intent)
        }
        waitUntil(8_000L) { NetworkShieldService.isActuallyRunning(target) }
        assertTrue(NetworkShieldService.isActuallyRunning(target))

        target.stopService(intent)
        waitUntil(8_000L) { !NetworkShieldService.isActuallyRunning(target) }
        assertFalse(NetworkShieldService.isActuallyRunning(target))
    }

    private fun waitUntil(timeoutMs: Long, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return
            Thread.sleep(250L)
        }
    }
}
