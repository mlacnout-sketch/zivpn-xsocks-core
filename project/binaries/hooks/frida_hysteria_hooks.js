/**
 * Frida script to hook Hysteria library functions
 * Usage: frida -U -f com.zivpn.app -l frida_hysteria_hooks.js
 */

console.log("[*] Hysteria Frida Hooks Loaded");

const LIB_UZ = "libuz.so";

function traceFunction(module, funcName, onEnter, onLeave) {
    const funcAddr = Module.findExportByName(module, funcName);

    if (!funcAddr) {
        console.log(`[-] Function ${funcName} not found in ${module}`);
        return;
    }

    console.log(`[+] Hooking ${funcName} @ ${funcAddr}`);

    Interceptor.attach(funcAddr, {
        onEnter: function(args) {
            this.startTime = Date.now();
            console.log(`\n[→] ${funcName} called`);
            if (onEnter) onEnter.call(this, args);
        },
        onLeave: function(retval) {
            const duration = Date.now() - this.startTime;
            console.log(`[←] ${funcName} returned: ${retval} (${duration}ms)`);
            if (onLeave) onLeave.call(this, retval);
        }
    });
}

function hookHysteriaFunctions() {
    console.log("\n[*] Setting up Hysteria function hooks...");

    traceFunction(LIB_UZ, "hysteria_connect",
        function(args) {
            console.log(`    Server: ${Memory.readUtf8String(args[0])}`);
            console.log(`    Port: ${args[1]}`);
        }
    );

    traceFunction(LIB_UZ, "hysteria_send",
        function(args) {
            const len = args[2].toInt32();
            console.log(`    Length: ${len} bytes`);
        }
    );
}

setImmediate(hookHysteriaFunctions);
