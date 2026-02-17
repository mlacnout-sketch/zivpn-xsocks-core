package com.minizivpn.app

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.Keep
import kotlin.math.min

/**
 * Background State enumeration
 */
enum class BackgroundState(val nativeValue: Int) {
    FOREGROUND(0),
    BACKGROUND(1),
    DOZE(2),
    LOW_MEMORY(3),
    BATTERY_SAVER(4);
    
    companion object {
        fun fromNative(value: Int): BackgroundState {
            return values().find { it.nativeValue == value } ?: FOREGROUND
        }
    }
}

/**
 * Process Priority enumeration
 */
enum class ProcessPriority(val nativeValue: Int) {
    CRITICAL(0),
    HIGH(1),
    NORMAL(2),
    LOW(3),
    BACKGROUND(4)
}

/**
 * Background Operation Manager
 * 
 * Manages native background processes, handles lifecycle,
 * and optimizes for battery and memory constraints.
 */
@Keep
object BackgroundOperationManager {
    private const val TAG = "BGOpManager"
    
    /* Native method stubs */
    private external fun initBackgroundManager()
    private external fun cleanupBackgroundManager()
    private external fun setBackgroundState(state: Int)
    private external fun getBackgroundState(): Int
    private external fun registerProcess(pid: Int, priority: Int): Int
    private external fun unregisterProcess(pid: Int): Int
    private external fun setProcessPriority(pid: Int, priority: Int): Int
    private external fun gracefulShutdown(pid: Int, timeoutMs: Int): Int
    private external fun getMemoryStats(stats: IntArray): Int
    private external fun isLowMemory(available: IntArray): Int
    private external fun requestCleanup(severity: Int): Int
    private external fun isDozeMode(): Int
    private external fun stateToString(state: Int): String
    
    private var initialized = false
    private var currentState = BackgroundState.FOREGROUND
    
    /**
     * Initialize background manager
     */
    fun initialize(context: Context) {
        if (initialized) {
            Log.d(TAG, "Background manager already initialized")
            return
        }
        
        try {
            initBackgroundManager()
            initialized = true
            Log.d(TAG, "Background operation manager initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize background manager", e)
        }
    }
    
    /**
     * Cleanup background manager
     */
    fun cleanup() {
        if (!initialized) return
        
        try {
            cleanupBackgroundManager()
            initialized = false
            Log.d(TAG, "Background operation manager cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup background manager", e)
        }
    }
    
    /**
     * Update background state based on system conditions
     */
    fun updateBackgroundState(state: BackgroundState) {
        if (!initialized) return
        
        if (state == currentState) {
            return  /* No change */
        }
        
        try {
            setBackgroundState(state.nativeValue)
            currentState = state
            Log.i(TAG, "Background state updated to ${state.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set background state", e)
        }
    }
    
    /**
     * Get current background state
     */
    fun getCurrentState(): BackgroundState {
        if (!initialized) return BackgroundState.FOREGROUND
        
        return try {
            BackgroundState.fromNative(getBackgroundState())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get background state", e)
            BackgroundState.FOREGROUND
        }
    }
    
    /**
     * Register process for background management
     */
    fun registerProcess(pid: Int, priority: ProcessPriority = ProcessPriority.NORMAL): Boolean {
        if (!initialized) {
            Log.w(TAG, "Background manager not initialized")
            return false
        }
        
        return try {
            val result = registerProcess(pid, priority.nativeValue)
            if (result == 0) {
                Log.d(TAG, "Process $pid registered with priority ${priority.name}")
                true
            } else {
                Log.w(TAG, "Failed to register process $pid")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering process $pid", e)
            false
        }
    }
    
    /**
     * Unregister process
     */
    fun unregisterProcess(pid: Int): Boolean {
        if (!initialized) return false
        
        return try {
            val result = unregisterProcess(pid)
            if (result == 0) {
                Log.d(TAG, "Process $pid unregistered")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering process $pid", e)
            false
        }
    }
    
    /**
     * Set process priority
     */
    fun setProcessPriority(pid: Int, priority: ProcessPriority): Boolean {
        if (!initialized) return false
        
        return try {
            val result = setProcessPriority(pid, priority.nativeValue)
            result == 0
        } catch (e: Exception) {
            Log.e(TAG, "Error setting process priority", e)
            false
        }
    }
    
    /**
     * Gracefully shutdown a process
     */
    fun gracefulShutdown(pid: Int, timeoutMs: Int = 5000): Boolean {
        if (!initialized) return false
        
        return try {
            val result = gracefulShutdown(pid, timeoutMs)
            result == 0
        } catch (e: Exception) {
            Log.e(TAG, "Error during graceful shutdown", e)
            false
        }
    }
    
    /**
     * Get memory statistics
     */
    fun getMemoryStats(): Pair<Int, Int>? {
        if (!initialized) return null
        
        return try {
            val stats = IntArray(2)
            val result = getMemoryStats(stats)
            if (result == 0) {
                Pair(stats[0], stats[1])  /* RSS MB, VMS MB */
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting memory stats", e)
            null
        }
    }
    
    /**
     * Check if low memory condition exists
     */
    fun isLowMemory(): Boolean {
        if (!initialized) return false
        
        return try {
            val available = IntArray(1)
            val result = isLowMemory(available)
            result == 1
        } catch (e: Exception) {
            Log.e(TAG, "Error checking low memory", e)
            false
        }
    }
    
    /**
     * Get available memory in MB
     */
    fun getAvailableMemoryMB(): Int? {
        if (!initialized) return null
        
        return try {
            val available = IntArray(1)
            val result = isLowMemory(available)
            if (result != -1) {
                available[0]
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting available memory", e)
            null
        }
    }
    
    /**
     * Request resource cleanup
     * severity: 1-10 (1 = minimal, 10 = aggressive)
     */
    fun requestCleanup(severity: Int = 5): Boolean {
        if (!initialized) return false
        
        val clampedSeverity = min(10, severity.coerceAtLeast(1))
        
        return try {
            val result = requestCleanup(clampedSeverity)
            if (result == 0) {
                Log.d(TAG, "Resource cleanup requested (severity: $clampedSeverity)")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting cleanup", e)
            false
        }
    }
    
    /**
     * Check if system is in doze mode
     */
    fun isDozeMode(): Boolean {
        if (!initialized) return false
        
        return try {
            isDozeMode() == 1
        } catch (e: Exception) {
            Log.e(TAG, "Error checking doze mode", e)
            false
        }
    }
    
    /**
     * Get state as string for logging
     */
    fun getStateString(state: BackgroundState): String {
        return try {
            stateToString(state.nativeValue)
        } catch (e: Exception) {
            state.name
        }
    }
    
    /**
     * Adapt performance based on current background state
     */
    fun adaptPerformance(context: Context) {
        if (!initialized) return
        
        val state = getCurrentState()
        val isLowMem = isLowMemory()
        val isDoze = isDozeMode()
        
        Log.d(TAG, "Adapting performance - State: $state, LowMem: $isLowMem, Doze: $isDoze")
        
        when {
            isDoze -> {
                /* In doze mode - minimize operations */
                requestCleanup(3)
            }
            isLowMem -> {
                /* Low memory - aggressive cleanup */
                requestCleanup(8)
            }
            state == BackgroundState.BACKGROUND -> {
                /* In background - reduced operations */
                requestCleanup(4)
            }
            state == BackgroundState.FOREGROUND -> {
                /* In foreground - normal operation */
                requestCleanup(1)
            }
        }
    }
}
