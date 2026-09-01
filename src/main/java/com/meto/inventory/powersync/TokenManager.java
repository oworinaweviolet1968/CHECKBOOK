package com.meto.inventory.powersync;

import com.meto.inventory.services.SupabaseService;

import java.util.Base64;
import java.util.concurrent.Callable;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Centralized token lifecycle manager with circuit breaker pattern.
 *
 * Responsibilities:
 * - Pre-emptive JWT refresh before expiry (avoids mid-operation 401s)
 * - Circuit breaker: max 3 consecutive refresh failures → 5-minute cooldown
 * - withValidToken(): wraps any API call with automatic 401 retry
 * - Auth state events for UI feedback
 *
 * Does NOT own tokens — delegates to SupabaseService for actual auth operations.
 */
public class TokenManager {
    private static TokenManager instance;

    // Circuit Breaker Configuration
    private static final int MAX_CONSECUTIVE_FAILURES = 3;
    private static final long COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes
    private static final long REFRESH_BUFFER_MS = 2 * 60 * 1000; // Refresh 2min before expiry

    // Circuit breaker state
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private volatile long cooldownUntilMs = 0;
    private volatile long tokenExpiryMs = 0;
    private final ReentrantLock refreshLock = new ReentrantLock();

    // Auth state
    public enum AuthState { AUTHENTICATED, DEGRADED, UNAUTHENTICATED }
    private volatile AuthState currentState = AuthState.UNAUTHENTICATED;
    private java.util.List<java.util.function.Consumer<AuthState>> authListeners =
            new java.util.concurrent.CopyOnWriteArrayList<>();

    private TokenManager() {}

    public static synchronized TokenManager getInstance() {
        if (instance == null) {
            instance = new TokenManager();
        }
        return instance;
    }

    // --- Auth State Observation ---

    public void addAuthStateListener(java.util.function.Consumer<AuthState> listener) {
        authListeners.add(listener);
    }

    public AuthState getCurrentState() {
        return currentState;
    }

    private void transitionTo(AuthState newState) {
        if (currentState != newState) {
            AuthState oldState = currentState;
            currentState = newState;
            System.out.println("TokenManager: Auth state " + oldState + " → " + newState);
            for (var listener : authListeners) {
                try {
                    listener.accept(newState);
                } catch (Exception ignored) {}
            }
        }
    }

    // --- Token Expiry Tracking ---

    /**
     * Called after every successful auth response (signIn, signInWithRefreshToken, etc.)
     * Parses the JWT to extract the `exp` claim and track expiry.
     */
    public void onTokenAcquired(String accessToken) {
        if (accessToken == null || accessToken.isEmpty()) return;
        try {
            tokenExpiryMs = parseJwtExpiry(accessToken);
            consecutiveFailures.set(0);
            cooldownUntilMs = 0;
            transitionTo(AuthState.AUTHENTICATED);
        } catch (Exception e) {
            // If we can't parse the JWT, assume 1 hour from now (Supabase default)
            tokenExpiryMs = System.currentTimeMillis() + (60 * 60 * 1000);
            transitionTo(AuthState.AUTHENTICATED);
        }
    }

    /**
     * Called on logout or session clear.
     */
    public void onTokenCleared() {
        tokenExpiryMs = 0;
        consecutiveFailures.set(0);
        cooldownUntilMs = 0;
        transitionTo(AuthState.UNAUTHENTICATED);
    }

    /**
     * Parses the `exp` claim from a Supabase JWT (standard base64url-encoded JWT).
     * Returns epoch milliseconds.
     */
    private long parseJwtExpiry(String jwt) {
        String[] parts = jwt.split("\\.");
        if (parts.length < 2) {
            throw new IllegalArgumentException("Invalid JWT format");
        }
        // Decode the payload (second segment)
        String payload = parts[1];
        // JWT uses base64url encoding — replace URL-safe chars and pad
        payload = payload.replace('-', '+').replace('_', '/');
        int pad = payload.length() % 4;
        if (pad > 0) {
            payload += "=".repeat(4 - pad);
        }
        byte[] decoded = Base64.getDecoder().decode(payload);
        String json = new String(decoded);

        // Parse "exp" field (Unix timestamp in seconds)
        com.google.gson.JsonObject obj = com.google.gson.JsonParser.parseString(json).getAsJsonObject();
        if (obj.has("exp")) {
            long expSeconds = obj.get("exp").getAsLong();
            return expSeconds * 1000; // Convert to milliseconds
        }
        throw new IllegalArgumentException("JWT missing 'exp' claim");
    }

    // --- Pre-emptive Refresh ---

    /**
     * Checks if the current token is within REFRESH_BUFFER_MS of expiry
     * and proactively refreshes it. Safe to call frequently (from auto-sync loop).
     * Returns true if the token is valid (either already valid or successfully refreshed).
     */
    public boolean ensureTokenFresh() {
        if (tokenExpiryMs == 0) return true; // No expiry known, assume valid

        long now = System.currentTimeMillis();
        long timeUntilExpiry = tokenExpiryMs - now;

        if (timeUntilExpiry > REFRESH_BUFFER_MS) {
            return true; // Token is fresh, nothing to do
        }

        if (timeUntilExpiry > 0) {
            System.out.println("TokenManager: Token expires in " + (timeUntilExpiry / 1000) + "s, pre-emptively refreshing...");
        } else {
            System.out.println("TokenManager: Token expired " + (Math.abs(timeUntilExpiry) / 1000) + "s ago, refreshing...");
        }

        return tryRefreshToken();
    }

    // --- Circuit Breaker Refresh ---

    /**
     * Attempts to refresh the token with circuit breaker protection.
     * - If in cooldown period, returns false immediately
     * - If max consecutive failures reached, enters cooldown and returns false
     * - On success, resets failure counter and updates expiry
     */
    public boolean tryRefreshToken() {
        long now = System.currentTimeMillis();

        // Check circuit breaker cooldown
        if (now < cooldownUntilMs) {
            long remainingSec = (cooldownUntilMs - now) / 1000;
            System.out.println("TokenManager: Circuit breaker active, cooldown " + remainingSec + "s remaining.");
            return false;
        }

        // Prevent concurrent refreshes
        if (!refreshLock.tryLock()) {
            return false; // Another thread is already refreshing
        }

        try {
            SupabaseService service = SupabaseService.getInstance();
            String refreshToken = service.getCurrentRefreshToken();

            if (refreshToken == null || refreshToken.isEmpty()) {
                System.err.println("TokenManager: No refresh token available.");
                transitionTo(AuthState.UNAUTHENTICATED);
                return false;
            }

            boolean success = service.signInWithRefreshToken(refreshToken);

            if (success) {
                consecutiveFailures.set(0);
                cooldownUntilMs = 0;
                // onTokenAcquired will be called by SupabaseService.parseAuthResponse
                System.out.println("TokenManager: Token refreshed successfully.");
                transitionTo(AuthState.AUTHENTICATED);
                return true;
            } else {
                int failures = consecutiveFailures.incrementAndGet();
                System.err.println("TokenManager: Refresh failed (" + failures + "/" + MAX_CONSECUTIVE_FAILURES + ")");

                if (failures >= MAX_CONSECUTIVE_FAILURES) {
                    cooldownUntilMs = now + COOLDOWN_MS;
                    System.err.println("TokenManager: Circuit breaker OPEN — cooldown until " +
                            java.time.Instant.ofEpochMilli(cooldownUntilMs));
                    transitionTo(AuthState.DEGRADED);
                }
                return false;
            }
        } catch (Exception e) {
            int failures = consecutiveFailures.incrementAndGet();
            System.err.println("TokenManager: Refresh exception (" + failures + "/" + MAX_CONSECUTIVE_FAILURES + "): " + e.getMessage());

            if (failures >= MAX_CONSECUTIVE_FAILURES) {
                cooldownUntilMs = System.currentTimeMillis() + COOLDOWN_MS;
                transitionTo(AuthState.DEGRADED);
            }
            return false;
        } finally {
            refreshLock.unlock();
        }
    }

    // --- Wrapped Execution ---

    /**
     * Execute an operation that requires a valid auth token.
     * Automatically ensures token freshness before execution.
     * On 401 failure, refreshes token and retries exactly once.
     *
     * Usage:
     *   TokenManager.getInstance().withValidToken(() -> {
     *       supabaseService.uploadDatabase(dbName, true);
     *       return null;
     *   });
     */
    public <T> T withValidToken(Callable<T> operation) throws Exception {
        ensureTokenFresh();

        try {
            return operation.call();
        } catch (java.io.IOException e) {
            if (e.getMessage() != null && e.getMessage().contains("401")) {
                System.out.println("TokenManager: 401 caught, attempting refresh and retry...");
                if (tryRefreshToken()) {
                    return operation.call(); // Retry exactly once
                } else {
                    throw new java.io.IOException("TokenManager: Token refresh failed, operation aborted.", e);
                }
            }
            throw e;
        }
    }

    /**
     * Fire-and-forget version for void operations.
     */
    public void withValidTokenVoid(Runnable operation) throws Exception {
        withValidToken(() -> {
            operation.run();
            return null;
        });
    }

    // --- Status ---

    public boolean isCircuitBreakerOpen() {
        return System.currentTimeMillis() < cooldownUntilMs;
    }

    public int getConsecutiveFailures() {
        return consecutiveFailures.get();
    }

    /**
     * Reset the circuit breaker (e.g., after a manual login).
     */
    public void resetCircuitBreaker() {
        consecutiveFailures.set(0);
        cooldownUntilMs = 0;
        transitionTo(AuthState.AUTHENTICATED);
    }
}
