package com.meto.inventory.powersync;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;

/**
 * Server-Client Clock Synchronization (NTP-lite).
 *
 * Hardened with:
 * - Rolling average over 5 samples to smooth network jitter
 * - Outlier rejection (rejects samples deviating >30s from current smoothed offset)
 * - Warning logger when clock drift exceeds 5s
 */
public class ClockSync {
    private static final int SAMPLE_WINDOW = 5;
    private static final long MAX_DEVIATION_MS = 30_000; // 30 seconds outlier threshold

    private static final Deque<Long> offsetSamples = new ArrayDeque<>();
    private static volatile long smoothedOffsetMs = 0;

    public static synchronized void updateClockOffset(long serverTimeEpochMs) {
        long localNow = System.currentTimeMillis();
        long rawOffset = serverTimeEpochMs - localNow;

        // Reject outlier samples if we already have a baseline
        if (!offsetSamples.isEmpty() && Math.abs(rawOffset - smoothedOffsetMs) > MAX_DEVIATION_MS) {
            System.err.println("ClockSync: Rejected outlier server time offset " + rawOffset +
                    "ms (smoothed=" + smoothedOffsetMs + "ms)");
            return;
        }

        offsetSamples.addLast(rawOffset);
        if (offsetSamples.size() > SAMPLE_WINDOW) {
            offsetSamples.removeFirst();
        }

        long sum = 0;
        for (long s : offsetSamples) {
            sum += s;
        }
        smoothedOffsetMs = sum / offsetSamples.size();

        if (Math.abs(smoothedOffsetMs) > 5000) {
            System.out.println("ClockSync: Significant clock skew detected: " + smoothedOffsetMs + "ms");
        }
    }

    public static long getClockOffsetMs() {
        return smoothedOffsetMs;
    }

    public static long getAdjustedEpochMs() {
        return System.currentTimeMillis() + smoothedOffsetMs;
    }

    public static String getAdjustedTimestampIso() {
        return Instant.ofEpochMilli(getAdjustedEpochMs()).toString();
    }
}
