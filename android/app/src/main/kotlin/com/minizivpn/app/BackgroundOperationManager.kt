package com.minizivpn.app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * Background Operation Manager
 * 
 * Manages background operations with WorkManager integration,
 * battery awareness, and graceful shutdown handling.
 */
class BackgroundOperationManager(private val context: Context) {
    
    companion object {
        private const val TAG = "BgOpManager"
        private const val WORK_TAG_BG_MONITOR = "bg_monitor"
        private const val WORK_TAG_HEALTH_CHECK = "health_check"
        
        // Background state constants
        const val STATE_FOREGROUND = 0
        const val STATE_BACKGROUND = 1
        const val STATE_DOZE = 2
        const val STATE_LOW_MEMORY = 3
        const val STATE_BATTERY_SAVER = 4
        
        // Process priority constants
        const val PRIORITY_CRITICAL = 0
        const val PRIORITY_HIGH = 1
        const val PRIORITY_NORMAL = 2
        const val PRIORITY_LOW = 3
        const val PRIORITY_BACKGROUND = 4
    }
    
    private val workManager = WorkManager.getInstance(context)
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val callbacks = mutableListOf<BackgroundStateCallback>()
    
    init {
        Log.d(TAG, "BackgroundOperationManager initialized")
    }
    
    /**
     * Initialize background monitoring
     */
    fun init() {
        Log.d(TAG, "Initializing background monitoring")
        
        // Initialize native background manager
        initializeNativeManager()
        
        // Schedule background monitoring
        scheduleBackgroundMonitoring()
        
        // Register battery receiver
        registerBatteryReceiver()
    }
    
    /**
     * Initialize native background manager
     */
    private fun initializeNativeManager() {
        try {
            BackgroundManager.bgInit()
            Log.d(TAG, "Native background manager initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize native background manager: ${e.message}")
        }
    }
    
    /**
     * Schedule background monitoring work
     */
    private fun scheduleBackgroundMonitoring() {
        val monitorWork = PeriodicWorkRequestBuilder<BackgroundMonitorWorker>(
            15, TimeUnit.MINUTES
        )
            .addTag(WORK_TAG_BG_MONITOR)
            .setConstraints(
                Constraints.Builder()
                    .setRequiresDeviceIdle(false)
                    .setRequiresBatteryNotLow(false)
                    .build()
            )
            .build()
        
        workManager.enqueueUniquePeriodicWork(
            WORK_TAG_BG_MONITOR,
            ExistingPeriodicWorkPolicy.KEEP,
            monitorWork
        )
        
        Log.d(TAG, "Scheduled background monitoring work")
    }
    
    /**
     * Register battery status receiver
     */
    private fun registerBatteryReceiver() {
        val batteryStatusFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        context.registerReceiver(
            BatteryStatusReceiver(this),
            batteryStatusFilter,
            Context.RECEIVER_NOT_EXPORTED
        )
    }
    
    /**
     * Update background state
     */
    fun setBackgroundState(state: Int) {
        Log.d(TAG, "Setting background state: $state")
        try {
            BackgroundManager.bgSetState(state)
            notifyStateChange(state)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set background state: ${e.message}")
        }
    }
    
    /**
     * Get current background state
     */
    fun getBackgroundState(): Int {
        return try {
            BackgroundManager.bgGetState()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get background state: ${e.message}")
            STATE_FOREGROUND
        }
    }
    
    /**
     * Register process for background management
     */
    fun registerProcess(pid: Int, priority: Int): Int {
        Log.d(TAG, "Registering process $pid with priority $priority")
        return try {
            BackgroundManager.bgRegisterProcess(pid, priority)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register process: ${e.message}")
            -1
        }
    }
    
    /**
     * Unregister process
     */
    fun unregisterProcess(pid: Int): Int {
        Log.d(TAG, "Unregistering process $pid")
        return try {
            BackgroundManager.bgUnregisterProcess(pid)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister process: ${e.message}")
            -1
        }
    }
    
    /**
     * Set process priority
     */
    fun setProcessPriority(pid: Int, priority: Int): Int {
        Log.d(TAG, "Setting process $pid priority to $priority")
        return try {
            BackgroundManager.bgSetPriority(pid, priority)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set process priority: ${e.message}")
            -1
        }
    }
    
    /**
     * Gracefully shutdown process
     */
    fun gracefulShutdown(pid: Int, timeoutMs: Int): Int {
        Log.d(TAG, "Initiating graceful shutdown for process $pid (timeout=${timeoutMs}ms)")
        return try {
            BackgroundManager.bgGracefulShutdown(pid, timeoutMs)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to graceful shutdown process: ${e.message}")
            -1
        }
    }
    
    /**
     * Get memory statistics
     */
    fun getMemoryStats(): Pair<Int, Int>? {
        return try {
            val stats = BackgroundManager.bgGetMemoryStats()
            if (stats != null && stats.size >= 2) {
                Pair(stats[0], stats[1])
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get memory stats: ${e.message}")
            null
        }
    }
    
    /**
     * Check if low memory condition
     */
    fun isLowMemory(): Boolean {
        return try {
            BackgroundManager.bgIsLowMemory() == 1
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check low memory: ${e.message}")
            false
        }
    }
    
    /**
     * Request cleanup with severity level
     */
    fun requestCleanup(severity: Int): Int {
        Log.d(TAG, "Requesting cleanup with severity $severity")
        return try {
            BackgroundManager.bgRequestCleanup(severity)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request cleanup: ${e.message}")
            -1
        }
    }
    
    /**
     * Check if in doze mode
     */
    fun isDozeMode(): Boolean {
        return try {
            BackgroundManager.bgIsDozeMode() == 1
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check doze mode: ${e.message}")
            powerManager.isDeviceIdleMode
        }
    }
    
    /**
     * Check if in battery saver mode
     */
    fun isBatterySaverMode(): Boolean {
        return try {
            powerManager.isPowerSaveMode
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check battery saver: ${e.message}")
            false
        }
    }
    
    /**
     * Check if battery is low
     */
    fun isBatteryLow(): Boolean {
        return try {
            val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = context.registerReceiver(null, intentFilter)
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val batteryPct = (level.toFloat() / scale.toFloat() * 100).toInt()
            batteryPct < 20
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check battery: ${e.message}")
            false
        }
    }
    
    /**
     * Register state callback
     */
    fun registerStateCallback(callback: BackgroundStateCallback) {
        callbacks.add(callback)
        Log.d(TAG, "Registered state callback")
    }
    
    /**
     * Unregister state callback
     */
    fun unregisterStateCallback(callback: BackgroundStateCallback) {
        callbacks.remove(callback)
        Log.d(TAG, "Unregistered state callback")
    }
    
    /**
     * Notify state change to all callbacks
     */
    private fun notifyStateChange(state: Int) {
        for (callback in callbacks) {
            callback.onStateChanged(state)
        }
    }
    
    /**
     * Update battery status
     */
    fun onBatteryStatusChanged(level: Int, scale: Int, status: Int) {
        val batteryPct = (level.toFloat() / scale.toFloat() * 100).toInt()
        Log.d(TAG, "Battery status: ${batteryPct}%")
        
        when {
            batteryPct < 15 -> setBackgroundState(STATE_BATTERY_SAVER)
            isDozeMode() -> setBackgroundState(STATE_DOZE)
            isLowMemory() -> setBackgroundState(STATE_LOW_MEMORY)
        }
    }
    
    /**
     * Cleanup
     */
    fun cleanup() {
        Log.d(TAG, "Cleaning up background operation manager")
        try {
            workManager.cancelAllWorkByTag(WORK_TAG_BG_MONITOR)
            workManager.cancelAllWorkByTag(WORK_TAG_HEALTH_CHECK)
            BackgroundManager.bgCleanup()
        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup: ${e.message}")
        }
    }
}

/**
 * Background state callback interface
 */
interface BackgroundStateCallback {
    fun onStateChanged(state: Int)
}

/**
 * Background monitor worker
 */
class BackgroundMonitorWorker(context: Context, params: WorkerParameters) : 
    Worker(context, params) {
    
    override fun doWork(): Result {
        return try {
            Log.d("BgMonitor", "Background monitoring check")
            Result.success()
        } catch (e: Exception) {
            Log.e("BgMonitor", "Error during background monitoring: ${e.message}")
            Result.retry()
        }
    }
}

/**
 * Battery status receiver
 */
class BatteryStatusReceiver(private val manager: BackgroundOperationManager) :
    android.content.BroadcastReceiver() {
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            
            manager.onBatteryStatusChanged(level, scale, status)
        }
    }
}

/**
 * Native background manager interface
 */
object BackgroundManager {
    external fun bgInit()
    external fun bgCleanup()
    external fun bgSetState(state: Int)
    external fun bgGetState(): Int
    external fun bgRegisterProcess(pid: Int, priority: Int): Int
    external fun bgUnregisterProcess(pid: Int): Int
    external fun bgSetPriority(pid: Int, priority: Int): Int
    external fun bgGracefulShutdown(pid: Int, timeoutMs: Int): Int
    external fun bgGetMemoryStats(): IntArray?
    external fun bgIsLowMemory(): Int
    external fun bgRequestCleanup(severity: Int): Int
    external fun bgIsDozeMode(): Int
    external fun bgGetStateString(state: Int): String
    external fun signalRegister(signum: Int): Int
    external fun signalUnregister(signum: Int): Int
    external fun signalBlock(signum: Int): Int
    external fun signalUnblock(signum: Int): Int
}
