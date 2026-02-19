cmake_minimum_required(VERSION 3.10...3.31)

project(minizivpn_native)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# --- Security & Sanitizer Options ---
option(ENABLE_SANITIZERS "Enable ASan and UBSan for Debug builds" ON)

if(CMAKE_BUILD_TYPE STREQUAL "Debug" AND ENABLE_SANITIZERS)
    message(STATUS "Enabling AddressSanitizer and UndefinedBehaviorSanitizer")
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

# Common security flags
add_compile_options(-fstack-protector-strong -D_FORTIFY_SOURCE=2)

option(TUN2SOCKS_ENABLE_LTO "Enable link-time optimization for tun2socks" ON)
option(TUN2SOCKS_ENABLE_CPU_TUNING "Enable ABI-specific CPU tuning flags" OFF)

# --- libancillary ---
add_library(ancillary STATIC
    libancillary/fd_recv.c
    libancillary/fd_send.c
)
target_include_directories(ancillary PUBLIC libancillary)

# --- tun2socks ---
set(BADVPN_SOURCES
    badvpn/base/BLog_syslog.c
    badvpn/system/BReactor_badvpn.c
    badvpn/system/BSignal.c
    badvpn/system/BConnection_unix.c
    badvpn/system/BTime.c
    badvpn/system/BUnixSignal.c
    badvpn/system/BNetwork.c
    badvpn/flow/StreamRecvInterface.c
    badvpn/flow/PacketRecvInterface.c
    badvpn/flow/PacketPassInterface.c
    badvpn/flow/StreamPassInterface.c
    badvpn/flow/SinglePacketBuffer.c
    badvpn/flow/BufferWriter.c
    badvpn/flow/PacketBuffer.c
    badvpn/flow/PacketStreamSender.c
    badvpn/flow/PacketPassConnector.c
    badvpn/flow/PacketProtoFlow.c
    badvpn/flow/PacketPassFairQueue.c
    badvpn/flow/PacketProtoEncoder.c
    badvpn/flow/PacketProtoDecoder.c
    badvpn/socksclient/BSocksClient.c
    badvpn/tuntap/BTap.c
    badvpn/lwip/src/core/timers.c
    badvpn/lwip/src/core/udp.c
    badvpn/lwip/src/core/memp.c
    badvpn/lwip/src/core/init.c
    badvpn/lwip/src/core/pbuf.c
    badvpn/lwip/src/core/tcp.c
    badvpn/lwip/src/core/tcp_out.c
    badvpn/lwip/src/core/netif.c
    badvpn/lwip/src/core/def.c
    badvpn/lwip/src/core/mem.c
    badvpn/lwip/src/core/tcp_in.c
    badvpn/lwip/src/core/stats.c
    badvpn/lwip/src/core/inet_chksum.c
    badvpn/lwip/src/core/ipv4/icmp.c
    badvpn/lwip/src/core/ipv4/igmp.c
    badvpn/lwip/src/core/ipv4/ip4_addr.c
    badvpn/lwip/src/core/ipv4/ip_frag.c
    badvpn/lwip/src/core/ipv4/ip4.c
    badvpn/lwip/src/core/ipv4/autoip.c
    badvpn/lwip/src/core/ipv6/ethip6.c
    badvpn/lwip/src/core/ipv6/inet6.c
    badvpn/lwip/src/core/ipv6/ip6_addr.c
    badvpn/lwip/src/core/ipv6/mld6.c
    badvpn/lwip/src/core/ipv6/dhcp6.c
    badvpn/lwip/src/core/ipv6/icmp6.c
    badvpn/lwip/src/core/ipv6/ip6.c
    badvpn/lwip/src/core/ipv6/ip6_frag.c
    badvpn/lwip/src/core/ipv6/nd6.c
    badvpn/lwip/custom/sys.c
    badvpn/tun2socks/tun2socks.c
    badvpn/base/DebugObject.c
    badvpn/base/BLog.c
    badvpn/base/BPending.c
    badvpn/system/BDatagram_unix.c
    badvpn/flowextra/PacketPassInactivityMonitor.c
    badvpn/tun2socks/SocksUdpGwClient.c
    badvpn/udpgw_client/UdpGwClient.c
    badvpn/tun2socks/MemoryPool.c
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
    libancillary
    badvpn/lwip/src/include/ipv4
    badvpn/lwip/src/include/ipv6
    badvpn/lwip/src/include
    badvpn/lwip/custom
    badvpn
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
        system/system.cpp
    )

    target_include_directories(system PRIVATE libancillary)
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
file(GLOB PDNSD_SOURCES "pdnsd/src/*.c")
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
target_include_directories(pdnsd PRIVATE pdnsd pdnsd/src)
target_link_libraries(pdnsd log)
