package com.meto.inventory.powersync;

import java.time.Instant;

public class ClockSync {
    private static long clockOffsetMs = 0;

    public static synchronized void updateClockOffset(long serverTimeEpochMs) {
        long localNow = System.currentTimeMillis();
        clockOffsetMs = serverTimeEpochMs - localNow;
    }

    public static long getAdjustedEpochMs() {
        return System.currentTimeMillis() + clockOffsetMs;
    }

    public static String getAdjustedTimestampIso() {
        return Instant.ofEpochMilli(getAdjustedEpochMs()).toString();
    }
}
