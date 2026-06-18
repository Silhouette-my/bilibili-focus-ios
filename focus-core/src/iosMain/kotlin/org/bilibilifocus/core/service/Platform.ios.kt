package org.bilibilifocus.core.service

import platform.Foundation.NSTimeZone

actual fun currentTimezoneOffsetMinutes(): Int {
    return -(NSTimeZone.localTimeZone.secondsFromGMT / 60)
}

actual fun currentEpochSeconds(): Long = platform.Foundation.NSDate().timeIntervalSince1970.toLong()
