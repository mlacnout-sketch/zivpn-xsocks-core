package com.minizivpn.app

import androidx.annotation.Keep

@Keep
class NativeSystem {
    companion object {
        init {
            System.loadLibrary("system")
        }

        @JvmStatic
        external fun jniclose(fd: Int)

        @JvmStatic
        external fun sendfd(tunFd: Int): Int

        @JvmStatic
        external fun getABI(): String
    }
}
