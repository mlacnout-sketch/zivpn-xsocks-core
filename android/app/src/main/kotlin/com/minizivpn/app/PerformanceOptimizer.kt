package com.minizivpn.app

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.util.Log
import kotlin.math.max
import kotlin.math.min

/**
 * Performance Optimizer
 * 
 * Monitors and optimizes performance based on system constraints
 */
class PerformanceOptimizer(private val context: Context) {
    
    companion object {
        private const val TAG = "PerfOptimizer"
        
        // Memory thresholds (MB)
        private const val MEMORY_CRITICAL = 50
        private const val MEMORY_LOW = 100
        private const val MEMORY_WARNING = 200
        
        // Thread pool settings
        private const val MIN_THREADS = 2
        private const val MAX_THREADS = 8
        
        // CPU throttling levels
        private const val THROTTLE_NONE = 0
        private const val THROTTLE_LOW = 1
        private const val THROTTLE_MEDIUM = 2
        private const val THROTTLE_HIGH = 3
    }
    
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private var currentThrottleLevel = THROTTLE_NONE
    private var optimalThreadCount = getOptimalThreadCount()
    
    /**
     * Get optimal thread count based on CPU cores and memory
     */
    private fun getOptimalThreadCount(): Int {
        val cpuCount = Runtime.getRuntime().availableProcessors()
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        
        val totalMemMb = memInfo.totalMem / (1024 * 1024)
        
        return when {
            totalMemMb < 2048 -> max(MIN_THREADS, cpuCount - 2)
            totalMemMb < 4096 -> cpuCount - 1
            else -> cpuCount
        }.coerceIn(MIN_THREADS, MAX_THREADS)
    }
    
    /**
     * Get recommended thread pool size
     */
    fun getRecommendedThreadPoolSize(): Int {
        val memoryStatus = getMemoryStatus()
        
        return when {
            memoryStatus.isLow -> min(optimalThreadCount, 2)
            memoryStatus.isCritical -> 1
            currentThrottleLevel == THROTTLE_HIGH -> max(MIN_THREADS, optimalThreadCount / 2)
            currentThrottleLevel == THROTTLE_MEDIUM -> (optimalThreadCount * 0.75).toInt()
            else -> optimalThreadCount
        }
    }
    
    /**
     * Get memory status
     */
    fun getMemoryStatus(): MemoryStatus {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        
        val availableMb = memInfo.availMem / (1024 * 1024)
        val totalMb = memInfo.totalMem / (1024 * 1024)
        val usedMb = totalMb - availableMb
        val usagePercent = (usedMb.toFloat() / totalMb.toFloat() * 100).toInt()
        
        val isCritical = availableMb < MEMORY_CRITICAL
        val isLow = availableMb < MEMORY_LOW
        val isWarning = availableMb < MEMORY_WARNING
        
        return MemoryStatus(
            totalMb = totalMb,
            usedMb = usedMb,
            availableMb = availableMb,
            usagePercent = usagePercent,
            isCritical = isCritical,
            isLow = isLow,
            isWarning = isWarning
        )
    }
    
    /**
     * Get native heap status
     */
    fun getNativeHeapStatus(): NativeHeapStatus {
        val totalSize = Debug.getNativeHeapSize()
        val totalAllocated = Debug.getNativeHeapAllocatedSize()
        val totalFree = Debug.getNativeHeapFreeSize()
        
        val totalSizeMb = (totalSize / (1024 * 1024)).toInt()
        val totalAllocatedMb = (totalAllocated / (1024 * 1024)).toInt()
        val totalFreeMb = (totalFree / (1024 * 1024)).toInt()
        
        val fragmentation = if (totalSize > 0) {
            ((totalFree.toFloat() / totalSize.toFloat()) * 100).toInt()
        } else {
            0
        }
        
        return NativeHeapStatus(
            totalMb = totalSizeMb,
            allocatedMb = totalAllocatedMb,
            freeMb = totalFreeMb,
            fragmentationPercent = fragmentation
        )
    }
    
    /**
     * Update CPU throttling level
     */
    fun updateThrottleLevel(cpuUsagePercent: Int) {
        val newLevel = when {
            cpuUsagePercent > 90 -> THROTTLE_HIGH
            cpuUsagePercent > 75 -> THROTTLE_MEDIUM
            cpuUsagePercent > 50 -> THROTTLE_LOW
            else -> THROTTLE_NONE
        }
        
        if (newLevel != currentThrottleLevel) {
            currentThrottleLevel = newLevel
            Log.d(TAG, "CPU throttle level changed to: $newLevel (usage: ${cpuUsagePercent}%)")
        }
    }
    
    /**
     * Get recommended buffer size
     */
    fun getRecommendedBufferSize(): Int {
        val memStatus = getMemoryStatus()
        
        return when {
            memStatus.isCritical -> 4 * 1024           // 4 KB
            memStatus.isLow -> 8 * 1024                // 8 KB
            memStatus.isWarning -> 16 * 1024           // 16 KB
            currentThrottleLevel >= THROTTLE_MEDIUM -> 32 * 1024  // 32 KB
            else -> 64 * 1024                          // 64 KB
        }
    }
    
    /**
     * Should enable aggressive GC
     */
    fun shouldEnableAggressiveGc(): Boolean {
        val memStatus = getMemoryStatus()
        return memStatus.isWarning || currentThrottleLevel >= THROTTLE_MEDIUM
    }
    
    /**
     * Get recommended batch size for operations
     */
    fun getRecommendedBatchSize(): Int {
        return when {
            currentThrottleLevel == THROTTLE_HIGH -> 10
            currentThrottleLevel == THROTTLE_MEDIUM -> 50
            currentThrottleLevel == THROTTLE_LOW -> 100
            else -> 200
        }
    }
    
    /**
     * Get CPU info
     */
    fun getCpuInfo(): CpuInfo {
        val cpuCount = Runtime.getRuntime().availableProcessors()
        
        return CpuInfo(
            cpuCount = cpuCount,
            throttleLevel = currentThrottleLevel,
            optimalThreadCount = optimalThreadCount
        )
    }
    
    /**
     * Request garbage collection
     */
    fun requestGarbageCollection() {
        Log.d(TAG, "Requesting garbage collection")
        System.gc()
    }
    
    /**
     * Get optimization recommendations
     */
    fun getOptimizationRecommendations(): List<String> {
        val recommendations = mutableListOf<String>()
        val memStatus = getMemoryStatus()
        val nativeHeap = getNativeHeapStatus()
        
        if (memStatus.isCritical) {
            recommendations.add("CRITICAL: Aggressive memory cleanup required")
            recommendations.add("Consider reducing thread pool size")
            recommendations.add("Enable compression for cached data")
        }
        
        if (memStatus.isLow) {
            recommendations.add("Memory usage high - reduce buffer sizes")
            recommendations.add("Enable periodic garbage collection")
        }
        
        if (nativeHeap.fragmentationPercent > 40) {
            recommendations.add("High native heap fragmentation - consider compaction")
        }
        
        if (currentThrottleLevel >= THROTTLE_MEDIUM) {
            recommendations.add("CPU throttling active - reduce intensive operations")
        }
        
        return recommendations
    }
    
    /**
     * Memory status data class
     */
    data class MemoryStatus(
        val totalMb: Long,
        val usedMb: Long,
        val availableMb: Long,
        val usagePercent: Int,
        val isCritical: Boolean,
        val isLow: Boolean,
        val isWarning: Boolean
    )
    
    /**
     * Native heap status
     */
    data class NativeHeapStatus(
        val totalMb: Int,
        val allocatedMb: Int,
        val freeMb: Int,
        val fragmentationPercent: Int
    )
    
    /**
     * CPU info
     */
    data class CpuInfo(
        val cpuCount: Int,
        val throttleLevel: Int,
        val optimalThreadCount: Int
    )
}
