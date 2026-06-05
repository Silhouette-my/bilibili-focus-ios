package org.bilibilifocus.core.crypto

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.CoreCrypto.CC_MD5
import platform.CoreCrypto.CC_MD5_DIGEST_LENGTH

@OptIn(ExperimentalForeignApi::class)
actual fun md5Hex(input: String): String {
    val bytes = input.encodeToByteArray()
    val digest = ByteArray(CC_MD5_DIGEST_LENGTH.toInt())
    bytes.usePinned { pinned ->
        digest.usePinned { digestPinned ->
            CC_MD5(pinned.addressOf(0), bytes.size.toUInt(), digestPinned.addressOf(0))
        }
    }
    return digest.joinToString("") { "%02x".format(it) }
}
