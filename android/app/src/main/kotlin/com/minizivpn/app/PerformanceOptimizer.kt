package com.minizivpn.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.util.Log
import androidx.annotation.Keep
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

/**
 * Performance Optimizer
 * 
 * Optimizes native process performance based on device conditions,
 * battery state, memory pressure, and system constraints.
 */
@Keep
class PerformanceOptimizer(private val context: Context) {
    
    companion object {
        private const val TAG = "PerfOptimizer"
        private const val LOW_MEMORY_THRESHOLD_MB = 100
        private const val CRITICAL_MEMORY_THRESHOLD_MB = 50
    }
    
    private val isOptimizing = AtomicBoolean(false)
    private var lastOptimizationTime = 0L
    private val optimizationIntervalMs = 5000  /* 5 seconds */
    
    /**
     * Perform performance optimization based on system state
     */
    fun optimize() {
        if (!isOptimizing.compareAndSet(false, true)) {
            return  /* Already optimizing */
        }
        
        try {
            val now = System.currentTimeMillis()
            if (now - lastOptimizationTime < optimizationIntervalMs) {
                return  /* Too soon */
            }
            
            lastOptimizationTime = now
            
            /* Analyze system state */
            val batteryState = getBatteryState()
            val memoryState = getMemoryState()
            val thermalState = getThermalState()
            
            /* Update background state based on conditions */
            updateBackgroundState(batteryState, memoryState, thermalState)
            
            /* Perform cleanup if needed */
            if (memoryState.isLowMemory) {
                performMemoryCleanup(memoryState)
            }
            
            /* Adjust process priorities */
            adjustProcessPriorities(batteryState, memoryState)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during optimization", e)
        } finally {
            isOptimizing.set(false)
        }
    }
    
    /**
     * Get current battery state
     */
    private fun getBatteryState(): BatteryState {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: 0
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: 100
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: BatteryManager.BATTERY_STATUS_UNKNOWN
        val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        
        val batteryPct = (level * 100) / max(1, scale)
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || 
                         status == BatteryManager.BATTERY_STATUS_FULL
        val isPlugged = plugged != 0
        
        return BatteryState(
            level = batteryPct,
            isCharging = isCharging,
            isPlugged = isPlugged
        )
    }
    
    /**
     * Get current memory state
     */
    private fun getMemoryState(): MemoryState {
        val runtime = Runtime.getRuntime()
        val totalMemory = runtime.totalMemory() / (1024 * 1024)
        val freeMemory = runtime.freeMemory() / (1024 * 1024)
        val usedMemory = totalMemory - freeMemory
        
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        
        val availableMem = memInfo.availMem / (1024 * 1024)
        val isLowMemory = memInfo.lowMemory || availableMem < LOW_MEMORY_THRESHOLD_MB
        val isCriticalMemory = availableMem < CRITICAL_MEMORY_THRESHOLD_MB
        
        return MemoryState(
            totalMemoryMB = totalMemory,
            usedMemoryMB = usedMemory,
            freeMemoryMB = freeMemory,
            availableMemoryMB = availableMem,
            isLowMemory = isLowMemory,
            isCriticalMemory = isCriticalMemory
        )
    }
    
    /**
     * Get thermal state (API 29+)
     */
    private fun getThermalState(): ThermalState {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return ThermalState(thermalStatus = 0)  /* THERMAL_STATUS_NONE */
        }
        
        val powerManager = context.getSystemService(Context.POWER_SERVICE) 
            as? android.os.PowerManager ?: return ThermalState(0)
        
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val method = powerManager.javaClass.getMethod("getCurrentThermalStatus")
                method.invoke(powerManager) as Int
            } catch (e: Exception) {
                0
            }
        } else {
            0
        }
        
        return ThermalState(thermalStatus = thermalStatus)
    }
    
    /**
     * Update background state based on system conditions
     */
    private fun updateBackgroundState(battery: BatteryState, memory: MemoryState, thermal: ThermalState) {
        val state = when {
            memory.isCriticalMemory -> BackgroundState.LOW_MEMORY
            battery.level < 20 && !battery.isPlugged -> BackgroundState.BATTERY_SAVER
            thermal.thermalStatus >= 2 -> BackgroundState.BACKGROUND  /* Throttling or critical */
            memory.isLowMemory -> BackgroundState.LOW_MEMORY
            else -> BackgroundState.FOREGROUND
        }
        
        BackgroundOperationManager.updateBackgroundState(state)
    }
    
    /**
     * Perform memory cleanup
     */
    private fun performMemoryCleanup(memory: MemoryState) {
        val severity = when {
            memory.isCriticalMemory -> 9
            memory.availableMemoryMB < 80 -> 7
            memory.availableMemoryMB < 120 -> 5
            else -> 3
        }
        
        Log.i(TAG, "Performing memory cleanup (severity: $severity, available: ${memory.availableMemoryMB}MB)")
        
        BackgroundOperationManager.requestCleanup(severity)
        
        /* Force garbage collection for critical memory */
        if (memory.isCriticalMemory) {
            System.gc()
        }
    }
    
    /**
     * Adjust process priorities based on system state
     */
    private fun adjustProcessPriorities(battery: BatteryState, memory: MemoryState) {
        val priority = when {
            memory.isCriticalMemory -> ProcessPriority.BACKGROUND
            battery.level < 15 && !battery.isPlugged -> ProcessPriority.LOW
            memory.isLowMemory -> ProcessPriority.LOW
            battery.isCharging || battery.isPlugged -> ProcessPriority.HIGH
            else -> ProcessPriority.NORMAL
        }
        
        Log.d(TAG, "Adjusted process priority to ${priority.name}")
    }
    
    /**
     * Get optimization metrics
     */
    fun getMetrics(): OptimizationMetrics {
        val battery = getBatteryState()
        val memory = getMemoryState()
        val thermal = getThermalState()
        
        return OptimizationMetrics(
            batteryLevel = battery.level,
            memoryUsage = memory.usedMemoryMB,
            availableMemory = memory.availableMemoryMB,
            thermalStatus = thermal.thermalStatus
        )
    }
    
    /**
     * Data class for battery state
     */
    data class BatteryState(
        val level: Int,
        val isCharging: Boolean,
        val isPlugged: Boolean
    )
    
    /**
     * Data class for memory state
     */
    data class MemoryState(
        val totalMemoryMB: Long,
        val usedMemoryMB: Long,
        val freeMemoryMB: Long,
        val availableMemoryMB: Long,
        val isLowMemory: Boolean,
        val isCriticalMemory: Boolean
    )
    
    /**
     * Data class for thermal state
     */
    data class ThermalState(
        val thermalStatus: Int
    )
    
    /**
     * Data class for optimization metrics
     */
    data class OptimizationMetrics(
        val batteryLevel: Int,
        val memoryUsage: Long,
        val availableMemory: Long,
        val thermalStatus: Int
    )
}
