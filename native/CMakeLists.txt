cmake_minimum_required(VERSION 3.10...3.31)

project(minizivpn_native)

option(TUN2SOCKS_ENABLE_LTO "Enable link-time optimization for tun2socks" ON)
option(TUN2SOCKS_ENABLE_CPU_TUNING "Enable ABI-specific CPU tuning flags" OFF)

# --- libancillary ---
add_library(ancillary STATIC
    src/libancillary/fd_recv.c
    src/libancillary/fd_send.c
)
target_include_directories(ancillary PUBLIC src/libancillary)

# --- tun2socks ---
set(BADVPN_SOURCES
    src/badvpn/base/BLog_syslog.c
    src/badvpn/system/BReactor_badvpn.c
    src/badvpn/system/BSignal.c
    src/badvpn/system/BConnection_unix.c
    src/badvpn/system/BTime.c
    src/badvpn/system/BUnixSignal.c
    src/badvpn/system/BNetwork.c
    src/badvpn/flow/StreamRecvInterface.c
    src/badvpn/flow/PacketRecvInterface.c
    src/badvpn/flow/PacketPassInterface.c
    src/badvpn/flow/StreamPassInterface.c
    src/badvpn/flow/SinglePacketBuffer.c
    src/badvpn/flow/BufferWriter.c
    src/badvpn/flow/PacketBuffer.c
    src/badvpn/flow/PacketStreamSender.c
    src/badvpn/flow/PacketPassConnector.c
    src/badvpn/flow/PacketProtoFlow.c
    src/badvpn/flow/PacketPassFairQueue.c
    src/badvpn/flow/PacketProtoEncoder.c
    src/badvpn/flow/PacketProtoDecoder.c
    src/badvpn/socksclient/BSocksClient.c
    src/badvpn/tuntap/BTap.c
    src/badvpn/lwip/src/core/timers.c
    src/badvpn/lwip/src/core/udp.c
    src/badvpn/lwip/src/core/memp.c
    src/badvpn/lwip/src/core/init.c
    src/badvpn/lwip/src/core/pbuf.c
    src/badvpn/lwip/src/core/tcp.c
    src/badvpn/lwip/src/core/tcp_out.c
    src/badvpn/lwip/src/core/netif.c
    src/badvpn/lwip/src/core/def.c
    src/badvpn/lwip/src/core/mem.c
    src/badvpn/lwip/src/core/tcp_in.c
    src/badvpn/lwip/src/core/stats.c
    src/badvpn/lwip/src/core/inet_chksum.c
    src/badvpn/lwip/src/core/ipv4/icmp.c
    src/badvpn/lwip/src/core/ipv4/igmp.c
    src/badvpn/lwip/src/core/ipv4/ip4_addr.c
    src/badvpn/lwip/src/core/ipv4/ip_frag.c
    src/badvpn/lwip/src/core/ipv4/ip4.c
    src/badvpn/lwip/src/core/ipv4/autoip.c
    src/badvpn/lwip/src/core/ipv6/ethip6.c
    src/badvpn/lwip/src/core/ipv6/inet6.c
    src/badvpn/lwip/src/core/ipv6/ip6_addr.c
    src/badvpn/lwip/src/core/ipv6/mld6.c
    src/badvpn/lwip/src/core/ipv6/dhcp6.c
    src/badvpn/lwip/src/core/ipv6/icmp6.c
    src/badvpn/lwip/src/core/ipv6/ip6.c
    src/badvpn/lwip/src/core/ipv6/ip6_frag.c
    src/badvpn/lwip/src/core/ipv6/nd6.c
    src/badvpn/lwip/custom/sys.c
    src/badvpn/tun2socks/tun2socks.c
    src/badvpn/base/DebugObject.c
    src/badvpn/base/BLog.c
    src/badvpn/base/BPending.c
    src/badvpn/system/BDatagram_unix.c
    src/badvpn/flowextra/PacketPassInactivityMonitor.c
    src/badvpn/tun2socks/SocksUdpGwClient.c
    src/badvpn/udpgw_client/UdpGwClient.c
    src/badvpn/tun2socks/MemoryPool.c
)

add_executable(tun2socks ${BADVPN_SOURCES})
set_target_properties(tun2socks PROPERTIES OUTPUT_NAME "tun2socks")
set_target_properties(tun2socks PROPERTIES SUFFIX ".so")
set_target_properties(tun2socks PROPERTIES PREFIX "lib")

target_compile_definitions(tun2socks PRIVATE
    BADVPN_THREADWORK_USE_PTHREAD
    BADVPN_LINUX
    BADVPN_BREACTOR_BADVPN
    _GNU_SOURCE
    BADVPN_USE_SELFPIPE
    BADVPN_USE_EPOLL
    BADVPN_LITTLE_ENDIAN
    BADVPN_THREAD_SAFE
    NDEBUG
    ANDROID
)

target_include_directories(tun2socks PRIVATE
    src/libancillary
    src/badvpn/lwip/src/include/ipv4
    src/badvpn/lwip/src/include/ipv6
    src/badvpn/lwip/src/include
    src/badvpn/lwip/custom
    src/badvpn
)

target_link_libraries(tun2socks ancillary log dl)

# Optimization flags
if(ANDROID)
    target_compile_options(tun2socks PRIVATE
        -O3
        -DNDEBUG
        -fno-plt
        -fvisibility=hidden
        -fomit-frame-pointer
    )

    if(TUN2SOCKS_ENABLE_LTO)
        target_compile_options(tun2socks PRIVATE -flto)
        target_link_options(tun2socks PRIVATE -flto)
    endif()

    target_link_options(tun2socks PRIVATE -Wl,--strip-all)

    # Architecture specific optimizations are disabled by default because some
    # devices/NDK combinations may not support the same tuning options.
    if(TUN2SOCKS_ENABLE_CPU_TUNING)
        if(ANDROID_ABI STREQUAL "arm64-v8a")
            target_compile_options(tun2socks PRIVATE -march=armv8-a+crypto)
        elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
            target_compile_options(tun2socks PRIVATE -mfpu=neon -mfloat-abi=softfp)
        endif()
    endif()
else()
    target_compile_options(tun2socks PRIVATE
        -O3
        -Wno-parentheses
        -Wno-pointer-sign
        -Wno-unused-value
        -Wno-unused-label
        -Wno-unused-variable
    )
endif()

if(NOT SKIP_JNI_CHECK)
    # --- system (JNI) ---
    add_library(system SHARED
        src/system/system.cpp
    )

    target_include_directories(system PRIVATE src/libancillary)
    target_compile_options(system PRIVATE -O3)

    # For android_getCpuFamily - Only include if running within NDK context
    if(ANDROID_NDK_REVISION OR ANDROID_PLATFORM)
        include(AndroidNdkModules)
        android_ndk_import_module_cpufeatures()
        target_link_libraries(system ancillary log dl cpufeatures)
        target_compile_definitions(system PRIVATE HAVE_CPU_FEATURES)
    else()
        target_link_libraries(system ancillary log dl)
    endif()
endif()

# --- pdnsd ---
file(GLOB PDNSD_SOURCES "src/pdnsd/src/*.c")
# Remove pdnsd-ctl.c if it exists in the glob to avoid multiple mains or conflicts
list(FILTER PDNSD_SOURCES EXCLUDE REGEX "pdnsd-ctl.c")

add_executable(pdnsd ${PDNSD_SOURCES})
set_target_properties(pdnsd PROPERTIES OUTPUT_NAME "pdnsd")
set_target_properties(pdnsd PROPERTIES SUFFIX ".so")
set_target_properties(pdnsd PROPERTIES PREFIX "lib")
target_compile_options(pdnsd PRIVATE 
    -Wall -O3 
    -Wno-deprecated-declarations 
    -Wno-unused-variable 
    -Wno-string-plus-int
    -Wno-gnu-designator
)
target_include_directories(pdnsd PRIVATE src/pdnsd src/pdnsd/src)
target_link_libraries(pdnsd log)
