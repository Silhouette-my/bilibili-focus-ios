package org.bilibilifocus.core.service

import java.util.TimeZone

actual fun currentTimezoneOffsetMinutes(): Int {
    return -(TimeZone.getDefault().rawOffset / 60_000)
}

actual fun currentEpochSeconds(): Long = System.currentTimeMillis() / 1000
