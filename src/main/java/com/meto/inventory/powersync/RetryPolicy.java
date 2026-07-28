package com.meto.inventory.powersync;

import java.util.Random;

public class RetryPolicy {
    private static final int INITIAL_DELAY_MS = 1000;
    private static final int MAX_DELAY_MS = 60000;
    private static final Random random = new Random();

    public static long calculateBackoffMs(int retryCount) {
        long delay = INITIAL_DELAY_MS * (1L << Math.min(retryCount, 10));
        long jitter = random.nextInt(1000);
        return Math.min(delay + jitter, MAX_DELAY_MS);
    }

    public static boolean isRetryableStatusCode(int statusCode) {
        return statusCode >= 500 || statusCode == 429 || statusCode == 408;
    }
}
