package com.meto.inventory.services;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.security.SecureRandom;
import java.util.Base64;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.concurrent.locks.ReentrantLock;

public class SupabaseService {

    // private static final Dotenv dotenv = Dotenv.load();
    private static final String SUPABASE_URL = "https://jhucvkqwenhyiveqsmtf.supabase.co";
    private static final String SUPABASE_KEY = "sb_publishable_UrI33FTSf-D4iuMReiqK5g_v7qc1l_-";

    // Derived Endpoints
    private static final String AUTH_URL = SUPABASE_URL + "/auth/v1";
    private static final String REST_URL = SUPABASE_URL + "/rest/v1";
    private static final String STORAGE_URL = SUPABASE_URL + "/storage/v1/object";

    private static SupabaseService instance;
    private final HttpClient client;
    private final ReentrantLock syncLock = new ReentrantLock();
    private String currentAccessToken;
    private String currentRefreshToken;
    private String currentUserId;

    private boolean lastSyncFailed = false;
    private java.util.List<java.util.function.Consumer<String>> statusListeners = new java.util.ArrayList<>();

    private SupabaseService() {
        this.client = HttpClient.newHttpClient();
        // Ensure data directory exists on init
        resolvePath("session_test.txt");
    }

    private String resolvePath(String fileName) {
        String userHome = System.getProperty("user.home");
        String appData = System.getenv("APPDATA");
        String rootDir = (appData != null) ? appData : userHome;

        java.io.File dir = new java.io.File(rootDir, "METO_IMS_DATA");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return new java.io.File(dir, fileName).getAbsolutePath();
    }

    public static synchronized SupabaseService getInstance() {
        if (instance == null) {
            instance = new SupabaseService();
        }
        return instance;
    }

    public void addStatusListener(java.util.function.Consumer<String> listener) {
        statusListeners.add(listener);
    }

    public void notifyStatus(String status) {
        for (java.util.function.Consumer<String> listener : statusListeners) {
            listener.accept(status);
        }
    }

    // --- AUTHENTICATION ---

    public boolean signUp(String email, String password) throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("email", email);
        payload.addProperty("password", password);

        // Supabase Auth Signup
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + "/signup"))
                .header("apikey", SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200 || response.statusCode() == 201) {
            parseAuthResponse(response.body());

            // Initial DB setup for new user
            ensureUserMetadataExists(email);
            return true;
        } else {
            handleAuthError(response);
            return false;
        }
    }

    public boolean adminCreateUser(String email, String password) throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("email", email);
        payload.addProperty("password", password);
        // Automatically confirm email if possible? No, requires service_role key.
        // But we can enable "auto_confirm" in Supabase dashboard if user wants.

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + "/signup"))
                .header("apikey", SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200 || response.statusCode() == 201) {
            // DO NOT parseAuthResponse (would overwrite Admin session)

            // Parse the new user's ID and email from the response so we can insert
            // a row into public.users immediately (admin's token is used for INSERT).
            try {
                com.google.gson.JsonObject newUserJson = com.google.gson.JsonParser.parseString(response.body()).getAsJsonObject();
                String newUserId = null;
                String newUserEmail = email;
                if (newUserJson.has("id")) {
                    newUserId = newUserJson.get("id").getAsString();
                } else if (newUserJson.has("user") && !newUserJson.get("user").isJsonNull()) {
                    com.google.gson.JsonObject userObj = newUserJson.getAsJsonObject("user");
                    if (userObj.has("id")) newUserId = userObj.get("id").getAsString();
                    if (userObj.has("email")) newUserEmail = userObj.get("email").getAsString();
                }

                if (newUserId != null) {
                    com.google.gson.JsonObject row = new com.google.gson.JsonObject();
                    row.addProperty("id", newUserId);
                    row.addProperty("email", newUserEmail);
                    row.addProperty("ownership_payment", false);
                    row.addProperty("monthly_cloud_backup", true);

                    HttpRequest insertReq = HttpRequest.newBuilder()
                            .uri(URI.create(REST_URL + "/users"))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", "Bearer " + currentAccessToken)
                            .header("Content-Type", "application/json")
                            .header("Prefer", "resolution=ignore-duplicates")
                            .POST(HttpRequest.BodyPublishers.ofString(row.toString()))
                            .build();
                    HttpResponse<String> insertRes = client.send(insertReq, HttpResponse.BodyHandlers.ofString());
                    System.out.println("DEBUG: adminCreateUser insert status=" + insertRes.statusCode() + " body=" + insertRes.body());
                }
            } catch (Exception ex) {
                System.err.println("adminCreateUser: failed to insert public.users row: " + ex.getMessage());
            }

            return true;
        } else {
            // Log error but don't throw to allow GUI to show it
            System.err.println("Admin Create User Failed: " + response.body());
            return false;
        }
    }

    public String lookupEmailByCheckbookId(String checkbookId) throws IOException, InterruptedException {
        if (checkbookId == null || checkbookId.trim().isEmpty()) {
            return null;
        }
        String rawInput = checkbookId.trim().toUpperCase();
        String formattedId = rawInput.startsWith("CK-") ? rawInput : "CK-" + rawInput;
        String rawDigits = rawInput.startsWith("CK-") ? rawInput.substring(3) : rawInput;

        String[] idVariations = new String[] { formattedId, rawDigits, rawInput };

        for (String idToTry : idVariations) {
            if (idToTry == null || idToTry.isEmpty()) continue;

            // 1. Primary: Try SECURITY DEFINER RPC endpoint (bypasses RLS)
            try {
                JsonObject rpcPayload = new JsonObject();
                rpcPayload.addProperty("p_checkbook_id", idToTry);

                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/rpc/rpc_lookup_user_by_checkbook_id"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(rpcPayload.toString()))
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                System.out.println("[RPC TRACE] POST /rpc/rpc_lookup_user_by_checkbook_id (" + idToTry + ") -> Status: " + response.statusCode() + ", Body: " + response.body());
                if (response.statusCode() == 200) {
                    JsonObject res = JsonParser.parseString(response.body()).getAsJsonObject();
                    if (res.has("found") && res.get("found").getAsBoolean() && res.has("email") && !res.get("email").isJsonNull()) {
                        if (res.has("user_id") && !res.get("user_id").isJsonNull()) {
                            this.currentUserId = res.get("user_id").getAsString();
                        }
                        return res.get("email").getAsString();
                    }
                }
            } catch (Exception e) {
                System.out.println("[RPC ERROR] Exception in RPC lookup: " + e.getMessage());
            }

            // 2. Query public.users directly
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/users?checkbook_id=eq." + idToTry + "&select=id,email"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .GET()
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                System.out.println("[REST TRACE] GET /users?checkbook_id=eq." + idToTry + " -> Status: " + response.statusCode() + ", Body: " + response.body());
                if (response.statusCode() == 200) {
                    JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                    if (arr.size() > 0) {
                        JsonObject obj = arr.get(0).getAsJsonObject();
                        if (obj.has("id") && !obj.get("id").isJsonNull()) {
                            this.currentUserId = obj.get("id").getAsString();
                        }
                        if (obj.has("email") && !obj.get("email").isJsonNull()) {
                            return obj.get("email").getAsString();
                        }
                    }
                }
            } catch (Exception e) {
                System.out.println("[REST ERROR] Exception in users query: " + e.getMessage());
            }

            // 3. user_profiles fallback
            try {
                HttpRequest queryRequest = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/user_profiles?checkbook_id=eq." + idToTry + "&select=user_id,email"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .GET()
                        .build();

                HttpResponse<String> queryResponse = client.send(queryRequest, HttpResponse.BodyHandlers.ofString());
                System.out.println("[REST TRACE] GET /user_profiles?checkbook_id=eq." + idToTry + " -> Status: " + queryResponse.statusCode() + ", Body: " + queryResponse.body());
                if (queryResponse.statusCode() == 200) {
                    JsonArray arr = JsonParser.parseString(queryResponse.body()).getAsJsonArray();
                    if (arr.size() > 0) {
                        JsonObject obj = arr.get(0).getAsJsonObject();
                        if (obj.has("user_id") && !obj.get("user_id").isJsonNull()) {
                            this.currentUserId = obj.get("user_id").getAsString();
                        }
                        if (obj.has("email") && !obj.get("email").isJsonNull()) {
                            return obj.get("email").getAsString();
                        }
                    }
                }
            } catch (Exception e) {
                System.out.println("[REST ERROR] Exception in user_profiles query: " + e.getMessage());
            }
        }

        return null;
    }

    public String lookupUserIdByCheckbookId(String checkbookId) throws IOException, InterruptedException {
        if (checkbookId == null || checkbookId.trim().isEmpty()) {
            return null;
        }
        String rawInput = checkbookId.trim().toUpperCase();
        String formattedId = rawInput.startsWith("CK-") ? rawInput : "CK-" + rawInput;
        String rawDigits = rawInput.startsWith("CK-") ? rawInput.substring(3) : rawInput;

        String[] idVariations = new String[] { formattedId, rawDigits, rawInput };

        for (String idToTry : idVariations) {
            if (idToTry == null || idToTry.isEmpty()) continue;

            // 1. Primary: Try SECURITY DEFINER RPC endpoint (bypasses RLS)
            try {
                JsonObject rpcPayload = new JsonObject();
                rpcPayload.addProperty("p_checkbook_id", idToTry);

                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/rpc/rpc_lookup_user_by_checkbook_id"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(rpcPayload.toString()))
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    JsonObject res = JsonParser.parseString(response.body()).getAsJsonObject();
                    if (res.has("found") && res.get("found").getAsBoolean() && res.has("user_id") && !res.get("user_id").isJsonNull()) {
                        return res.get("user_id").getAsString();
                    }
                }
            } catch (Exception ignore) {}

            // 2. Direct query public.users by checkbook_id column
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/users?checkbook_id=eq." + idToTry + "&select=id"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .GET()
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                    if (arr.size() > 0) {
                        JsonObject obj = arr.get(0).getAsJsonObject();
                        if (obj.has("id") && !obj.get("id").isJsonNull()) {
                            return obj.get("id").getAsString();
                        }
                    }
                }
            } catch (Exception ignore) {}
        }

        return null;
    }

    public boolean signInWithCheckbookId(String checkbookId) throws IOException, InterruptedException {
        String email = lookupEmailByCheckbookId(checkbookId);
        String userId = lookupUserIdByCheckbookId(checkbookId);

        if (userId == null || userId.isEmpty()) {
            return false;
        }

        this.currentUserId = userId;
        saveSession();
        ensureUserMetadataExists(email);
        return true;
    }

    public JsonObject initiatePairingRequest(String checkbookId) throws IOException, InterruptedException {
        String formattedId = checkbookId.trim().toUpperCase();
        if (!formattedId.startsWith("CK-")) {
            formattedId = "CK-" + formattedId;
        }

        String email = lookupEmailByCheckbookId(formattedId);
        if (email == null || email.trim().isEmpty()) {
            // Also try raw input
            email = lookupEmailByCheckbookId(checkbookId.trim());
        }

        if (email == null || email.trim().isEmpty()) {
            JsonObject err = new JsonObject();
            err.addProperty("success", false);
            err.addProperty("message", "Checkbook ID not found. Please verify your Checkbook ID under Mobile App > Settings > Checkbook ID.");
            return err;
        }

        String targetEmail = email.trim();
        String targetUserId = lookupUserIdByCheckbookId(formattedId);
        if (targetUserId == null || targetUserId.trim().isEmpty()) {
            targetUserId = lookupUserIdByCheckbookId(checkbookId.trim());
        }

        if (targetUserId != null && !targetUserId.trim().isEmpty()) {
            this.currentUserId = targetUserId.trim();
        }

        // Purge existing pending login requests for this target identifier first
        try {
            String encodedTarget = java.net.URLEncoder.encode(targetEmail, java.nio.charset.StandardCharsets.UTF_8);
            HttpRequest deleteOld = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/login_requests?email=eq." + encodedTarget + "&status=eq.pending"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + SUPABASE_KEY)
                    .DELETE()
                    .build();
            client.send(deleteOld, HttpResponse.BodyHandlers.ofString());
        } catch (Exception ignored) {}

        JsonObject row = new JsonObject();
        row.addProperty("email", targetEmail);
        row.addProperty("status", "pending");

        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/login_requests"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .header("Prefer", "return=representation")
                .POST(HttpRequest.BodyPublishers.ofString(row.toString()))
                .build();

        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() == 201 || resp.statusCode() == 200) {
            JsonArray arr = JsonParser.parseString(resp.body()).getAsJsonArray();
            if (arr.size() > 0) {
                JsonObject createdObj = arr.get(0).getAsJsonObject();
                String sessionId = createdObj.get("id").getAsString();
                JsonObject ret = new JsonObject();
                ret.addProperty("success", true);
                ret.addProperty("session_id", sessionId);
                ret.addProperty("email", targetEmail);
                if (targetUserId != null && !targetUserId.isEmpty()) {
                    ret.addProperty("user_id", targetUserId);
                }
                return ret;
            }
        }

        JsonObject err = new JsonObject();
        err.addProperty("success", false);
        err.addProperty("message", "Failed to initiate pairing request. Please check connection and try again.");
        return err;
    }

    public JsonObject checkPairingStatus(String sessionId) throws IOException, InterruptedException {
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/login_requests?id=eq." + sessionId + "&select=*"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + SUPABASE_KEY)
                .GET()
                .build();

        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() == 200) {
            JsonArray arr = JsonParser.parseString(resp.body()).getAsJsonArray();
            if (arr.size() > 0) {
                JsonObject row = arr.get(0).getAsJsonObject();
                String st = row.has("status") ? row.get("status").getAsString() : "pending";
                JsonObject ret = new JsonObject();
                ret.addProperty("found", true);
                ret.addProperty("status", st.toUpperCase());
                if (row.has("refresh_token") && !row.get("refresh_token").isJsonNull()) {
                    ret.addProperty("pairing_token", row.get("refresh_token").getAsString());
                }
                if (row.has("email") && !row.get("email").isJsonNull()) {
                    ret.addProperty("email", row.get("email").getAsString());
                }
                return ret;
            }
        }

        JsonObject ret = new JsonObject();
        ret.addProperty("found", false);
        ret.addProperty("status", "NOT_FOUND");
        return ret;
    }

    public void savePairingToken(String token, String userId, String email) {
        if (token != null) {
            try {
                JsonObject json = new JsonObject();
                json.addProperty("pairing_token", token);
                json.addProperty("user_id", userId);
                json.addProperty("email", email);
                json.addProperty("refresh_token", token);
                String encryptedData = encrypt(json.toString());
                Files.writeString(Path.of(resolvePath("user_session.txt")), encryptedData);
                this.currentUserId = userId;
                this.currentRefreshToken = token;
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    public boolean verifyStoredTokenOnStartup() {
        String storedContent = loadSession();
        if (storedContent == null || storedContent.trim().isEmpty()) {
            return false;
        }
        try {
            JsonObject json = null;
            try {
                json = JsonParser.parseString(storedContent).getAsJsonObject();
            } catch (Exception e) {
                json = new JsonObject();
                json.addProperty("pairing_token", storedContent);
            }

            String token = json.has("pairing_token") ? json.get("pairing_token").getAsString() : (json.has("refresh_token") ? json.get("refresh_token").getAsString() : storedContent);
            String savedUserId = json.has("user_id") && !json.get("user_id").isJsonNull() ? json.get("user_id").getAsString() : null;
            String savedEmail = json.has("email") && !json.get("email").isJsonNull() ? json.get("email").getAsString() : null;

            if (savedUserId != null && !savedUserId.trim().isEmpty()) {
                this.currentUserId = savedUserId.trim();
            }
            if (this.currentUserId == null || this.currentUserId.trim().isEmpty()) {
                try {
                    Path activeUserPath = Path.of(resolvePath("active_user.txt"));
                    if (Files.exists(activeUserPath)) {
                        String uid = Files.readString(activeUserPath).trim();
                        if (!uid.isEmpty() && uid.length() > 10) {
                            this.currentUserId = uid;
                        }
                    }
                } catch (Exception ignore) {}
            }
            if (token != null && !token.trim().isEmpty()) {
                this.currentRefreshToken = token.trim();
                this.currentAccessToken = token.trim();
            }

            boolean tokenValid = false;
            try {
                JsonObject payload = new JsonObject();
                payload.addProperty("p_pairing_token", token);

                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/rpc/rpc_verify_device_token"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    JsonObject res = JsonParser.parseString(response.body()).getAsJsonObject();
                    if (res.has("valid") && res.get("valid").getAsBoolean()) {
                        if (res.has("user_id") && !res.get("user_id").isJsonNull()) {
                            this.currentUserId = res.get("user_id").getAsString();
                        }
                        tokenValid = true;
                    }
                }
            } catch (Exception ignore) {}

            // Fallback for persistent user session
            if (!tokenValid && this.currentUserId != null && !this.currentUserId.trim().isEmpty()) {
                tokenValid = true;
            }

            if (tokenValid) {
                try {
                    JsonObject metadata = getUserMetadata(this.currentUserId, savedEmail);
                    if (metadata != null && metadata.size() > 0) {
                        if (!isOwnershipOrTrialValid(metadata)) {
                            System.err.println("Startup ownership verification failed: License/Trial expired. Purging session.");
                            clearSession();
                            return false;
                        }
                    }
                } catch (Exception ignore) {}

                // Persistent Login Verified!
                return true;
            }
        } catch (Exception e) {
            System.err.println("verifyStoredTokenOnStartup error: " + e.getMessage());
        }
        return false;
    }

    public JsonObject getUserMetadata(String targetUserId, String targetEmail) {
        JsonObject result = new JsonObject();
        String uid = (targetUserId != null && !targetUserId.isEmpty()) ? targetUserId : this.currentUserId;
        String email = (targetEmail != null && !targetEmail.isEmpty()) ? targetEmail : null;

        if (uid != null && !uid.isEmpty()) {
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/users?id=eq." + uid + "&select=*"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .GET()
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                    if (arr.size() > 0) {
                        return arr.get(0).getAsJsonObject();
                    }
                }
            } catch (Exception ignore) {}
        }

        if (email != null && !email.isEmpty()) {
            try {
                String encodedEmail = java.net.URLEncoder.encode(email, java.nio.charset.StandardCharsets.UTF_8);
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/users?email=eq." + encodedEmail + "&select=*"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .GET()
                        .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                    if (arr.size() > 0) {
                        return arr.get(0).getAsJsonObject();
                    }
                }
            } catch (Exception ignore) {}
        }

        try {
            return getUserMetadata();
        } catch (Exception ignore) {}

        return result;
    }

    public boolean isOwnershipOrTrialValid(JsonObject metadata) {
        if (metadata == null || metadata.size() == 0) return true;

        if (isTrialActive(metadata)) {
            return true;
        }

        boolean ownershipPaid = true;
        if (metadata.has("ownership_payment") && !metadata.get("ownership_payment").isJsonNull()) {
            ownershipPaid = metadata.get("ownership_payment").getAsBoolean();
        }

        if (metadata.has("ownership_expiry") && !metadata.get("ownership_expiry").isJsonNull()) {
            try {
                long expiry = metadata.get("ownership_expiry").getAsLong();
                if (expiry > 0 && System.currentTimeMillis() > expiry) {
                    ownershipPaid = false;
                }
            } catch (Exception ignore) {}
        }

        return ownershipPaid;
    }

    private boolean isTrialActive(JsonObject metadata) {
        if (metadata == null || metadata.size() == 0) return true;
        long now = System.currentTimeMillis();

        String createdStr = null;
        if (metadata.has("trial_started_at") && !metadata.get("trial_started_at").isJsonNull()) {
            createdStr = metadata.get("trial_started_at").getAsString();
        } else if (metadata.has("created_at") && !metadata.get("created_at").isJsonNull()) {
            createdStr = metadata.get("created_at").getAsString();
        } else if (metadata.has("installed_at") && !metadata.get("installed_at").isJsonNull()) {
            createdStr = metadata.get("installed_at").getAsString();
        }

        if (createdStr != null && !createdStr.trim().isEmpty()) {
            long createdMs = parseIsoTimestamp(createdStr);
            if (createdMs > 0) {
                long diffMs = now - createdMs;
                if (diffMs < (7L * 24 * 3600 * 1000)) {
                    return true;
                }
            } else {
                return true;
            }
        }

        if (createdStr == null || createdStr.trim().isEmpty()) {
            if (!metadata.has("ownership_payment") || metadata.get("ownership_payment").isJsonNull() || metadata.get("ownership_payment").getAsBoolean()) {
                return true;
            }
        }

        return false;
    }

    private long parseIsoTimestamp(String dateStr) {
        if (dateStr == null || dateStr.trim().isEmpty()) return 0L;
        String s = dateStr.trim();
        try {
            return java.time.Instant.parse(s).toEpochMilli();
        } catch (Exception e1) {
            try {
                return java.time.OffsetDateTime.parse(s).toInstant().toEpochMilli();
            } catch (Exception e2) {
                try {
                    String clean = s.replace(" ", "T");
                    if (!clean.contains("Z") && !clean.contains("+") && clean.indexOf('-', 5) > 0) {
                        clean += "Z";
                    }
                    return java.time.Instant.parse(clean).toEpochMilli();
                } catch (Exception e3) {
                    try {
                        return Long.parseLong(s);
                    } catch (Exception e4) {
                        return 0L;
                    }
                }
            }
        }
    }

    public String loadSession() {
        try {
            Path path = Path.of(resolvePath("user_session.txt"));
            if (Files.exists(path)) {
                String content = Files.readString(path).trim();
                try {
                    String decrypted = decrypt(content);
                    if (decrypted.startsWith("{") && decrypted.endsWith("}")) {
                        try {
                            JsonObject json = JsonParser.parseString(decrypted).getAsJsonObject();
                            if (json.has("user_id") && !json.get("user_id").isJsonNull()) {
                                this.currentUserId = json.get("user_id").getAsString();
                            }
                        } catch (Exception ignore) {}
                    }
                    return decrypted;
                } catch (Exception e) {
                    System.err.println("Session decryption failed. Fallback to plain text.");
                    return content; 
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }

    public boolean sendPasswordResetEmail(String email, String redirectUrl) throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("email", email);

        String fullUrl = AUTH_URL + "/recover";
        if (redirectUrl != null && !redirectUrl.isEmpty()) {
            fullUrl += "?redirect_to="
                    + java.net.URLEncoder.encode(redirectUrl, java.nio.charset.StandardCharsets.UTF_8);
        }

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(fullUrl))
                .header("apikey", SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200 || response.statusCode() == 201) {
            return true;
        } else {
            System.err.println("Reset Password Failed: " + response.body());
            return false;
        }
    }

    public boolean signIn(String email, String password) throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("email", email);
        payload.addProperty("password", password);

        // Supabase Auth Login
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + "/token?grant_type=password"))
                .header("apikey", SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            parseAuthResponse(response.body());
            saveSession();
            // Ensure metadata exists (in case user was created in dashboard or signUp
            // failed to create it)
            ensureUserMetadataExists(email);
            return true;
        } else {
            handleAuthError(response);
            return false;
        }
    }

    public boolean signInWithRefreshToken(String refreshToken) throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("refresh_token", refreshToken);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + "/token?grant_type=refresh_token"))
                .header("apikey", SUPABASE_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            parseAuthResponse(response.body());
            saveSession();
            return true;
        } else {
            System.err.println("signInWithRefreshToken failed: Status " + response.statusCode() + " - " + response.body());
            if (response.statusCode() == 400 || response.statusCode() == 401) {
                System.err.println("Refresh token invalid. Clearing expired access token and session.");
                this.currentAccessToken = null;
                this.currentRefreshToken = null;
                clearSession();
            }
            return false;
        }
    }

    public boolean signInWithAccessToken(String accessToken, String refreshToken) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + "/user"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + accessToken)
                .GET()
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            JsonObject userObj = JsonParser.parseString(response.body()).getAsJsonObject();
            this.currentAccessToken = accessToken;
            this.currentRefreshToken = refreshToken != null ? refreshToken : "";
            this.currentUserId = userObj.get("id").getAsString();
            saveSession();
            ensureUserMetadataExists(userObj.has("email") ? userObj.get("email").getAsString() : null);
            return true;
        } else {
            System.err.println("signInWithAccessToken failed: Status " + response.statusCode() + " - " + response.body());
            clearSession();
            return false;
        }
    }

    public void logout() {
        this.currentAccessToken = null;
        this.currentRefreshToken = null;
        this.currentUserId = null;
        clearSession();
        // Notify TokenManager to reset circuit breaker
        try {
            com.meto.inventory.powersync.TokenManager.getInstance().onTokenCleared();
        } catch (Exception ignored) {}
    }

    public static class SessionConflictInfo {
        public final String activeDeviceId;
        public final String activeDeviceName;
        public final String lastActive;

        public SessionConflictInfo(String activeDeviceId, String activeDeviceName, String lastActive) {
            this.activeDeviceId = activeDeviceId;
            this.activeDeviceName = activeDeviceName;
            this.lastActive = lastActive;
        }
    }

    public SessionConflictInfo checkSessionConflict(String targetUserId, String category) {
        if (currentAccessToken == null) return null;
        try {
            String currentDeviceId = com.meto.inventory.powersync.DeviceIdentity.getDeviceId();
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(SUPABASE_URL + "/rest/v1/user_sessions?user_id=eq." + targetUserId + "&select=*"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    JsonObject obj = arr.get(0).getAsJsonObject();
                    String slotKey = "desktop".equals(category) ? "active_desktop_device_id" : "active_mobile_device_id";
                    String nameKey = "desktop".equals(category) ? "active_desktop_device_name" : "active_mobile_device_name";
                    String timeKey = "desktop".equals(category) ? "active_desktop_last_active" : "active_mobile_last_active";

                    if (obj.has(slotKey) && !obj.get(slotKey).isJsonNull()) {
                        String activeId = obj.get(slotKey).getAsString();
                        if (activeId != null && !activeId.isEmpty() && !activeId.equals(currentDeviceId)) {
                            String activeName = obj.has(nameKey) && !obj.get(nameKey).isJsonNull() ? obj.get(nameKey).getAsString() : ("Another " + category + " Device");
                            String lastActive = obj.has(timeKey) && !obj.get(timeKey).isJsonNull() ? obj.get(timeKey).getAsString() : "recently";
                            return new SessionConflictInfo(activeId, activeName, lastActive);
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("checkSessionConflict error: " + e.getMessage());
        }
        return null;
    }

    public void registerSession(String targetUserId, String category, boolean force) {
        if (currentAccessToken == null) return;
        try {
            String currentDeviceId = com.meto.inventory.powersync.DeviceIdentity.getDeviceId();
            String deviceName = "desktop".equals(category) ? "Desktop PC (" + System.getProperty("os.name") + ")" : "Mobile App";
            String nowIso = java.time.Instant.now().toString();

            JsonObject payload = new JsonObject();
            payload.addProperty("user_id", targetUserId);
            payload.addProperty("updated_at", nowIso);

            if ("desktop".equals(category)) {
                payload.addProperty("active_desktop_device_id", currentDeviceId);
                payload.addProperty("active_desktop_device_name", deviceName);
                payload.addProperty("active_desktop_last_active", nowIso);
            } else {
                payload.addProperty("active_mobile_device_id", currentDeviceId);
                payload.addProperty("active_mobile_device_name", deviceName);
                payload.addProperty("active_mobile_last_active", nowIso);
            }

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(SUPABASE_URL + "/rest/v1/user_sessions"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=merge-duplicates")
                    .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            System.out.println("REGISTER SESSION (" + category + ") status: " + response.statusCode());
        } catch (Exception e) {
            System.err.println("registerSession error: " + e.getMessage());
        }
    }

    public boolean verifyCurrentSessionValid() {
        if (currentUserId == null || currentAccessToken == null) return true;
        try {
            String currentDeviceId = com.meto.inventory.powersync.DeviceIdentity.getDeviceId();
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(SUPABASE_URL + "/rest/v1/user_sessions?user_id=eq." + currentUserId + "&select=active_desktop_device_id"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    JsonObject obj = arr.get(0).getAsJsonObject();
                    if (obj.has("active_desktop_device_id") && !obj.get("active_desktop_device_id").isJsonNull()) {
                        String activeId = obj.get("active_desktop_device_id").getAsString();
                        if (activeId != null && !activeId.isEmpty() && !activeId.equals(currentDeviceId)) {
                            System.err.println("DESKTOP SESSION REVOKED by device " + activeId);
                            return false;
                        }
                    }
                }
            }
        } catch (Exception ignored) {}
        return true;
    }

    private void saveSession() {
        if (currentRefreshToken != null) {
            try {
                JsonObject json = new JsonObject();
                json.addProperty("refresh_token", currentRefreshToken);
                if (currentUserId != null) {
                    json.addProperty("user_id", currentUserId);
                }
                String encryptedData = encrypt(json.toString());
                Files.writeString(Path.of(resolvePath("user_session.txt")), encryptedData);
            } catch (Exception e) {
                System.err.println("Encryption failed, saving plain-text fallback (NOT SECURE)");
                e.printStackTrace();
            }
        }
    }



    public void clearSession() {
        try {
            Files.deleteIfExists(Path.of(resolvePath("user_session.txt")));
            this.currentUserId = null;
            this.currentAccessToken = null;
            this.currentRefreshToken = null;
            // Notify TokenManager to reset state
            try {
                com.meto.inventory.powersync.TokenManager.getInstance().onTokenCleared();
            } catch (Exception ignored) {}
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // --- ENCRYPTION HELPERS ---

    private String encrypt(String data) throws Exception {
        byte[] salt = "METO_IMS_SALT_2024".getBytes();
        SecretKey key = getEncryptionKey(salt);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        byte[] iv = new byte[12];
        new SecureRandom().nextBytes(iv);
        GCMParameterSpec spec = new GCMParameterSpec(128, iv);
        cipher.init(Cipher.ENCRYPT_MODE, key, spec);

        byte[] cipherText = cipher.doFinal(data.getBytes());
        ByteBuffer bb = ByteBuffer.allocate(iv.length + cipherText.length);
        bb.put(iv);
        bb.put(cipherText);

        return Base64.getEncoder().encodeToString(bb.array());
    }

    private String decrypt(String encryptedData) throws Exception {
        byte[] decoded = Base64.getDecoder().decode(encryptedData);
        ByteBuffer bb = ByteBuffer.wrap(decoded);
        byte[] iv = new byte[12];
        bb.get(iv);
        byte[] cipherText = new byte[bb.remaining()];
        bb.get(cipherText);

        byte[] salt = "METO_IMS_SALT_2024".getBytes();
        SecretKey key = getEncryptionKey(salt);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        GCMParameterSpec spec = new GCMParameterSpec(128, iv);
        cipher.init(Cipher.DECRYPT_MODE, key, spec);

        byte[] plainText = cipher.doFinal(cipherText);
        return new String(plainText);
    }

    private SecretKey getEncryptionKey(byte[] salt) throws Exception {
        String hardwareId = System.getProperty("user.name") + getMacAddress();
        SecretKeyFactory factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
        // 1000 iterations is plenty for local desktop app binding
        PBEKeySpec spec = new PBEKeySpec(hardwareId.toCharArray(), salt, 1000, 256);
        SecretKey tmp = factory.generateSecret(spec);
        return new SecretKeySpec(tmp.getEncoded(), "AES");
    }

    private String getMacAddress() {
        try {
            java.util.Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            for (NetworkInterface ni : Collections.list(interfaces)) {
                byte[] mac = ni.getHardwareAddress();
                if (mac != null && mac.length > 0) {
                    StringBuilder sb = new StringBuilder();
                    for (int i = 0; i < mac.length; i++) {
                        sb.append(String.format("%02X", mac[i]));
                    }
                    return sb.toString();
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return "FALLBACK_HARDWARE_ID";
    }

    private void parseAuthResponse(String body) {
        JsonObject json = JsonParser.parseString(body).getAsJsonObject();
        if (json.has("access_token")) {
            this.currentAccessToken = json.get("access_token").getAsString();
        }
        if (json.has("refresh_token")) {
            this.currentRefreshToken = json.get("refresh_token").getAsString();
        }
        if (json.has("user")) {
            this.currentUserId = json.getAsJsonObject("user").get("id").getAsString();
        }
        // Notify TokenManager of new token for pre-emptive refresh tracking
        if (this.currentAccessToken != null) {
            try {
                com.meto.inventory.powersync.TokenManager.getInstance().onTokenAcquired(this.currentAccessToken);
            } catch (Exception ignored) {}
        }
    }

    private void handleAuthError(HttpResponse<String> response) throws IOException {
        String msg = "Auth Failed: " + response.statusCode();
        try {
            JsonObject json = JsonParser.parseString(response.body()).getAsJsonObject();
            if (json.has("msg"))
                msg = json.get("msg").getAsString();
            if (json.has("error_description"))
                msg = json.get("error_description").getAsString();
        } catch (Exception ignore) {
        }
        System.err.println(msg);
        throw new IOException(msg);
    }

    public boolean isSyncFailed() {
        return lastSyncFailed;
    }

    /**
     * Lightweight check if the cloud service is reachable.
     */
    public boolean isOnline() {
        try {
            // Heartbeat against Supabase Auth (health check)
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(AUTH_URL + "/health"))
                    .header("apikey", SUPABASE_KEY)
                    .GET()
                    .timeout(java.time.Duration.ofSeconds(3))
                    .build();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            return response.statusCode() == 200;
        } catch (Exception e) {
            return false;
        }
    }

    // --- DATABASE (METADATA) ---

    private void ensureUserMetadataExists(String email) {
        // Check if metadata already exists to avoid overwriting (e.g. ownership status)
        try {
            JsonObject existing = getUserMetadata();
            if (existing != null && existing.size() > 0) {
                // Metadata exists, do not overwrite default values
                return;
            }
        } catch (Exception e) {
            // If fetch fails (e.g. 404), proceed to create
        }

        // We need to insert a row into public.users if it doesn't exist.
        // upsert: POST /rest/v1/users?on_conflict=id

        try {
            JsonObject row = new JsonObject();
            row.addProperty("id", currentUserId);
            row.addProperty("email", email);
            // Defaults
            row.addProperty("ownership_payment", false);
            row.addProperty("monthly_cloud_backup", true);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/users"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=ignore-duplicates") // CHANGED: ignore if exists
                    .POST(HttpRequest.BodyPublishers.ofString(row.toString()))
                    .build();

            client.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public JsonObject getUserMetadata() throws IOException, InterruptedException {
        if (currentUserId == null)
            throw new IOException("Not logged in");

        JsonObject result = new JsonObject();

        // 1. GET /rest/v1/users?id=eq.UID&select=*
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/users?id=eq." + currentUserId + "&select=*"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + (currentAccessToken != null ? currentAccessToken : SUPABASE_KEY))
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    result = arr.get(0).getAsJsonObject();
                }
            }
        } catch (Exception ignore) {}

        // 2. Merge /rest/v1/user_profiles?user_id=eq.UID&select=*
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/user_profiles?user_id=eq." + currentUserId + "&select=*"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + (currentAccessToken != null ? currentAccessToken : SUPABASE_KEY))
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    JsonObject profile = arr.get(0).getAsJsonObject();
                    for (String key : profile.keySet()) {
                        if (!result.has(key) || result.get(key).isJsonNull()) {
                            result.add(key, profile.get(key));
                        }
                    }
                }
            }
        } catch (Exception ignore) {}

        // 3. Ensure checkbook_id is present and dynamic (never literal asterisks)
        if (!result.has("checkbook_id") || result.get("checkbook_id").isJsonNull() || result.get("checkbook_id").getAsString().contains("*")) {
            String newId = generateUniqueCheckbookId();
            result.addProperty("checkbook_id", newId);
            try {
                JsonObject patch = new JsonObject();
                patch.addProperty("checkbook_id", newId);
                patch.addProperty("user_id", currentUserId);

                HttpRequest patchReq = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/user_profiles"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + SUPABASE_KEY)
                        .header("Content-Type", "application/json")
                        .header("Prefer", "resolution=merge-duplicates")
                        .POST(HttpRequest.BodyPublishers.ofString(patch.toString()))
                        .build();

                client.send(patchReq, HttpResponse.BodyHandlers.ofString());
            } catch (Exception ignore) {}
        }

        return result;
    }

    public static String generateUniqueCheckbookId() {
        java.util.Random rand = new java.util.Random();
        int code = 100000 + rand.nextInt(900000);
        return "CK-" + code;
    }

    public void updateUserFields(Map<String, Object> updates) throws IOException, InterruptedException {
        if (currentUserId == null)
            throw new IOException("Not logged in");

        JsonObject json = new JsonObject();
        updates.forEach((k, v) -> {
            if (v instanceof String)
                json.addProperty(k, (String) v);
            else if (v instanceof Boolean)
                json.addProperty(k, (Boolean) v);
            else if (v instanceof Number)
                json.addProperty(k, (Number) v);
        });

        // 1. Primary: PATCH /rest/v1/user_profiles?user_id=eq.UID
        HttpRequest req1 = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/user_profiles?user_id=eq." + currentUserId))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", getValidBearerToken())
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                .build();

        HttpResponse<String> res1 = client.send(req1, HttpResponse.BodyHandlers.ofString());
        if (res1.statusCode() >= 200 && res1.statusCode() < 300) {
            return;
        }

        // 2. Fallback: PATCH /rest/v1/users?id=eq.UID
        HttpRequest req2 = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/users?id=eq." + currentUserId))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", getValidBearerToken())
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                .build();

        HttpResponse<String> res2 = client.send(req2, HttpResponse.BodyHandlers.ofString());
        if (res2.statusCode() > 299) {
            System.err.println("updateUserFields failed on both tables: " + res2.statusCode() + " " + res2.body());
        }
    }

    /**
     * Lightweight heartbeat — PATCHes desktop_last_seen (epoch ms) to the users table.
     * Called every 10s by the AutoSync thread. Does NOT hold the sync lock.
     */
    public void updateHeartbeat() {
        sendHeartbeatPing();
    }

    public String getValidBearerToken() {
        if (currentAccessToken != null && currentAccessToken.startsWith("eyJ") && currentAccessToken.split("\\.").length == 3) {
            return "Bearer " + currentAccessToken;
        }
        return "Bearer " + SUPABASE_KEY;
    }

    /**
     * Sends heartbeat ping and returns true if HTTP 2xx, false otherwise (e.g. 401 or network drop).
     * Updates desktop_last_seen on user_profiles (primary) and users (fallback).
     */
    public boolean sendHeartbeatPing() {
        if (currentUserId == null) return false;
        try {
            long now = System.currentTimeMillis();
            
            // 1. Try SECURITY DEFINER RPC first (bypasses RLS)
            JsonObject rpcPayload = new JsonObject();
            rpcPayload.addProperty("p_user_id", currentUserId);
            rpcPayload.addProperty("p_timestamp", now);

            HttpRequest rpcReq = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/rpc/rpc_update_desktop_presence"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + SUPABASE_KEY)
                    .header("Content-Type", "application/json")
                    .timeout(java.time.Duration.ofSeconds(5))
                    .POST(HttpRequest.BodyPublishers.ofString(rpcPayload.toString()))
                    .build();

            HttpResponse<String> rpcRes = client.send(rpcReq, HttpResponse.BodyHandlers.ofString());
            System.out.println("[HEARTBEAT TRACE] POST /rpc/rpc_update_desktop_presence (" + currentUserId + ", " + now + ") -> Status: " + rpcRes.statusCode() + ", Body: " + rpcRes.body());
            if (rpcRes.statusCode() >= 200 && rpcRes.statusCode() < 300) {
                return true;
            }

            // 2. Direct PATCH fallback
            JsonObject json = new JsonObject();
            json.addProperty("desktop_last_seen", now);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/user_profiles?user_id=eq." + currentUserId))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .timeout(java.time.Duration.ofSeconds(5))
                    .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            return response.statusCode() >= 200 && response.statusCode() < 300;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Lightweight API availability verification (HEAD request to /stock?limit=1).
     */
    public boolean verifyAPIAvailability() {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/stock?limit=1"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .timeout(java.time.Duration.ofSeconds(4))
                    .method("HEAD", HttpRequest.BodyPublishers.noBody())
                    .build();

            HttpResponse<Void> response = client.send(request, HttpResponse.BodyHandlers.discarding());
            return response.statusCode() == 200 || response.statusCode() == 206;
        } catch (Exception e) {
            return false;
        }
    }

    // --- STORAGE (BACKUPS) ---

    public boolean uploadDatabase(String filePath) {
        return uploadDatabase(filePath, false);
    }

    public boolean uploadDatabase(String filePath, boolean isSilent) {
        try {
            if (!syncLock.tryLock(5, java.util.concurrent.TimeUnit.SECONDS)) {
                System.out.println("SYNC: Upload skipped - lock timeout.");
                lastSyncFailed = true; // FORCE RETRY
                return false;
            }
        } catch (InterruptedException e) {
            System.out.println("SYNC: Upload interrupted while waiting for lock.");
            lastSyncFailed = true;
            return false;
        }
        try {
            if (currentUserId == null) {
                lastSyncFailed = true;
                return false;
            }

            com.meto.inventory.DatabaseHelper db = com.meto.inventory.DataManager.getInstance().getDbHelper();
            
            return pushPendingChangesInternal(db, isSilent);
        } catch (IOException e) {
            if (e.getMessage() != null && e.getMessage().contains("401")) {
                System.out.println("SYNC: Token expired (401), attempting to refresh session and retry...");
                boolean refreshed = false;
                try {
                    if (currentRefreshToken != null) {
                        refreshed = signInWithRefreshToken(currentRefreshToken);
                    }
                } catch (Exception refreshEx) {
                    System.err.println("SYNC: Token refresh failed: " + refreshEx.getMessage());
                }
                // Retry the failed operation once with the new token
                if (refreshed) {
                    try {
                        com.meto.inventory.DatabaseHelper retryDb = com.meto.inventory.DataManager.getInstance().getDbHelper();
                        return pushPendingChangesInternal(retryDb, isSilent);
                    } catch (Exception retryEx) {
                        System.err.println("SYNC: Retry after token refresh failed: " + retryEx.getMessage());
                    }
                }
            } else {
                e.printStackTrace();
            }
            lastSyncFailed = true;
            return false;
        } catch (Exception e) {
            e.printStackTrace();
            lastSyncFailed = true;
            return false;
        } finally {
            syncLock.unlock();
        }
    }

    // --- RECEIPT SETTINGS SYNC VIA STORAGE ---

    /**
     * Uploads the local receipt settings to Supabase Storage as a JSON file.
     * Called after saving receipt settings on the desktop.
     */
    public void uploadReceiptSettings() {
        try {
            if (currentUserId == null || currentAccessToken == null) return;

            var db = com.meto.inventory.DataManager.getInstance().getDbHelper();
            JsonObject settings = new JsonObject();
            String[] keys = {"receipt_shop_name", "receipt_shop_number", "receipt_location", "receipt_phone", "receipt_phone2"};
            for (String key : keys) {
                String val = db.getSetting(key);
                settings.addProperty(key, val != null ? val : "");
            }
            String passcode = db.getSetting("passcode");
            if (passcode != null && !passcode.isEmpty()) {
                settings.addProperty("passcode", passcode);
            }

            byte[] jsonBytes = settings.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
            String storagePath = currentUserId + "/settings.json";

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(STORAGE_URL + "/backups/" + storagePath))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .header("x-upsert", "true")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(jsonBytes))
                    .build();

            HttpResponse<String> res = client.send(request, HttpResponse.BodyHandlers.ofString());
            System.out.println("SETTINGS UPLOAD: " + res.statusCode());
            invalidateSettingsCache();
        } catch (Exception e) {
            System.err.println("Failed to upload receipt settings: " + e.getMessage());
        }
    }

    private long lastSettingsCheckTime = 0;

    public void invalidateSettingsCache() {
        this.lastSettingsCheckTime = 0;
    }

    /**
     * Downloads receipt settings from Supabase Storage and saves them locally.
     * Called during syncOnLogin to ensure desktop has the latest receipt info.
     */
    public void downloadReceiptSettings() {
        if (System.currentTimeMillis() - lastSettingsCheckTime < 600000) {
            return;
        }
        lastSettingsCheckTime = System.currentTimeMillis();
        try {
            if (currentUserId == null || currentAccessToken == null) return;

            String storagePath = currentUserId + "/settings.json";

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(STORAGE_URL + "/backups/" + storagePath))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .GET()
                    .build();

            HttpResponse<String> res = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (res.statusCode() == 200) {
                try {
                    JsonObject settings = JsonParser.parseString(res.body()).getAsJsonObject();
                    var db = com.meto.inventory.DataManager.getInstance().getDbHelper();
                    String[] keys = {"receipt_shop_name", "receipt_shop_number", "receipt_location", "receipt_phone", "receipt_phone2", "passcode"};
                    for (String key : keys) {
                        if (settings.has(key) && !settings.get(key).isJsonNull()) {
                            String cloudVal = settings.get(key).getAsString();
                            String localVal = db.getSetting(key);
                            // Only overwrite if cloud has data and local is empty
                            // (to avoid overwriting intentional local edits)
                            if (!cloudVal.isEmpty() && (localVal == null || localVal.isEmpty())) {
                                db.saveSetting(key, cloudVal);
                            }
                            // If local has no value at all, always accept cloud
                            if (localVal == null) {
                                db.saveSetting(key, cloudVal);
                            }
                        }
                    }
                    System.out.println("SETTINGS DOWNLOAD: Applied receipt settings from cloud");
                } catch (Exception parseEx) {
                    System.err.println("SETTINGS DOWNLOAD: Failed to parse settings JSON: " + parseEx.getMessage());
                }
            } else {
                System.out.println("SETTINGS DOWNLOAD: No settings file found (" + res.statusCode() + ")");
            }
        } catch (Exception e) {
            System.err.println("Failed to download receipt settings: " + e.getMessage());
        }
    }

    // --- PROGRESS TRACKING ---
    private final java.util.List<java.util.function.Consumer<Double>> progressListeners = new java.util.ArrayList<>();

    public void addProgressListener(java.util.function.Consumer<Double> listener) {
        progressListeners.add(listener);
    }

    @SuppressWarnings("unused")
    private void notifyProgress(double progress) {
        javafx.application.Platform.runLater(() -> {
            for (var listener : progressListeners) {
                listener.accept(progress);
            }
        });
    }

    private boolean pushPendingChangesInternal(com.meto.inventory.DatabaseHelper db, boolean isSilent) throws Exception {
        // Check for changes
        JsonArray dirtyStock = db.getDirtyStock();
        JsonArray dirtySales = db.getDirtySales();
        JsonArray delStock = db.getDirtyDeletedStock();
        JsonArray delSales = db.getDirtyDeletedHistory();

        boolean hasChanges = dirtyStock.size() > 0 || dirtySales.size() > 0 || delStock.size() > 0 || delSales.size() > 0;
        if (!hasChanges) {
            notifyStatus("Cloud: Synced");
            return true; // Silent success
        }

        if (!isSilent) {
            notifyStatus("Syncing with Postgres...");
        }
        
        // --- 1. PUSH ---
        // STOCK (Option A: Metadata updates only — quantity deltas are handled via DeltaStockManager)
        boolean stockUploadSuccess = true;
        if (dirtyStock.size() > 0) {
            String nowIso = com.meto.inventory.powersync.ClockSync.getAdjustedTimestampIso();
            JsonArray metadataStock = new JsonArray();

            for (JsonElement el : dirtyStock) {
                JsonObject o = el.getAsJsonObject();
                JsonObject metaObj = new JsonObject();
                metaObj.addProperty("sync_id", o.get("sync_id").getAsString());
                metaObj.addProperty("user_id", currentUserId);
                metaObj.addProperty("updated_at", nowIso);
                if (o.has("item")) metaObj.addProperty("item", o.get("item").getAsString());
                if (o.has("unit")) metaObj.addProperty("unit", o.get("unit").getAsString());
                if (o.has("price")) metaObj.addProperty("price", o.get("price").getAsString());
                if (o.has("cost_price")) metaObj.addProperty("cost_price", o.get("cost_price").getAsDouble());
                if (o.has("base_quantity")) metaObj.addProperty("base_quantity", o.get("base_quantity").getAsDouble());
                if (o.has("device_source")) metaObj.addProperty("device_source", o.get("device_source").getAsString());
                if (o.has("date")) metaObj.addProperty("date", o.get("date").getAsString());
                metadataStock.add(metaObj);
            }

            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/stock?on_conflict=sync_id"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=merge-duplicates")
                    .POST(HttpRequest.BodyPublishers.ofString(metadataStock.toString()))
                    .build();
            HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
            System.out.println("STOCK METADATA UPLOAD RESPONSE: " + res.statusCode() + " " + res.body());
            if (res.statusCode() == 401) {
                throw new IOException("SYNC: Stock upload returned 401 - token expired");
            }
            if (res.statusCode() >= 300) {
                stockUploadSuccess = false;
            }
        }
        
        boolean salesUploadSuccess = true;
        if (dirtySales.size() > 0) {
            String nowIso = java.time.Instant.now().toString();
            for (JsonElement el : dirtySales) {
                JsonObject o = el.getAsJsonObject();
                o.addProperty("user_id", currentUserId);
                o.addProperty("updated_at", nowIso);
            }
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/sales?on_conflict=sync_id"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=merge-duplicates")
                    .POST(HttpRequest.BodyPublishers.ofString(dirtySales.toString()))
                    .build();
            HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
            System.out.println("SALES UPLOAD RESPONSE: " + res.statusCode() + " " + res.body());
            if (res.statusCode() == 401) {
                throw new IOException("SYNC: Sales upload returned 401 - token expired");
            }
            if (res.statusCode() >= 300) {
                salesUploadSuccess = false;
            }
        }

        // DELETIONS
        if (delStock.size() > 0) {
            for (com.google.gson.JsonElement el : delStock) {
                com.google.gson.JsonObject o = el.getAsJsonObject();
                String syncId = o.has("sync_id") && !o.get("sync_id").isJsonNull() ? o.get("sync_id").getAsString() : null;
                String item = o.has("item") && !o.get("item").isJsonNull() ? o.get("item").getAsString() : null;
                String quantity = o.has("quantity") && !o.get("quantity").isJsonNull() ? o.get("quantity").getAsString() : null;

                if (syncId != null && !syncId.isEmpty()) {
                    HttpRequest req = HttpRequest.newBuilder()
                            .uri(URI.create(REST_URL + "/stock?sync_id=eq." + java.net.URLEncoder.encode(syncId, java.nio.charset.StandardCharsets.UTF_8)))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", getValidBearerToken())
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
                if (item != null && quantity != null) {
                    HttpRequest req = HttpRequest.newBuilder()
                            .uri(URI.create(REST_URL + "/stock?item=eq." + java.net.URLEncoder.encode(item, java.nio.charset.StandardCharsets.UTF_8) + "&quantity=eq." + java.net.URLEncoder.encode(quantity, java.nio.charset.StandardCharsets.UTF_8)))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", getValidBearerToken())
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
            }
        }

        if (delSales.size() > 0) {
            for (com.google.gson.JsonElement el : delSales) {
                com.google.gson.JsonObject o = el.getAsJsonObject();
                String syncId = o.has("sync_id") && !o.get("sync_id").isJsonNull() ? o.get("sync_id").getAsString() : null;
                String customer = o.has("customer") && !o.get("customer").isJsonNull() ? o.get("customer").getAsString() : "";
                String item = o.has("item") && !o.get("item").isJsonNull() ? o.get("item").getAsString() : "";
                String amount = o.has("amount") && !o.get("amount").isJsonNull() ? o.get("amount").getAsString() : "";
                String date = o.has("date") && !o.get("date").isJsonNull() ? o.get("date").getAsString() : "";

                if (syncId != null && !syncId.isEmpty()) {
                    HttpRequest req = HttpRequest.newBuilder()
                            .uri(URI.create(REST_URL + "/sales?sync_id=eq." + java.net.URLEncoder.encode(syncId, java.nio.charset.StandardCharsets.UTF_8)))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", getValidBearerToken())
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
                if (!item.isEmpty() && !date.isEmpty()) {
                    String url = REST_URL + "/sales?item=eq." + java.net.URLEncoder.encode(item, java.nio.charset.StandardCharsets.UTF_8) + "&date=eq." + java.net.URLEncoder.encode(date, java.nio.charset.StandardCharsets.UTF_8);
                    if (!customer.isEmpty() && !"Walk-in Customer".equalsIgnoreCase(customer)) {
                        url += "&customer=eq." + java.net.URLEncoder.encode(customer, java.nio.charset.StandardCharsets.UTF_8);
                    }
                    if (!amount.isEmpty()) {
                        url += "&amount=eq." + java.net.URLEncoder.encode(amount, java.nio.charset.StandardCharsets.UTF_8);
                    }
                    HttpRequest req = HttpRequest.newBuilder()
                            .uri(URI.create(url))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", getValidBearerToken())
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
            }
        }

        if (stockUploadSuccess && salesUploadSuccess) {
            db.clearDirtyFlags();
            lastSyncFailed = false;

            // Only update backup timestamp on successful sync
            long ts = System.currentTimeMillis();
            Map<String, Object> updates = new HashMap<>();
            updates.put("last_backup_timestamp", ts);
            updateUserFields(updates);
            db.saveSetting("last_backup_timestamp", String.valueOf(ts));
            notifyStatus("Cloud: " + new java.util.Date(ts).toString());
        } else {
            lastSyncFailed = true;
            System.err.println("SYNC: Preserving dirty flags because cloud POST upload returned non-2xx status code.");
            notifyStatus("Cloud: Sync Failed");
        }

        return stockUploadSuccess && salesUploadSuccess;
    }

    public boolean syncOnLogin(String dbPath, boolean localHasData, boolean isManual) {
        if (!syncLock.tryLock()) return false;
        try {
            if (currentUserId == null) return false;

            com.meto.inventory.DatabaseHelper db = com.meto.inventory.DataManager.getInstance().getDbHelper();
            db.checkAutoResyncMigration();

            String localVersionStr = db.getSetting("last_backup_timestamp");
            long localVersionTs = (localVersionStr != null) ? Long.parseLong(localVersionStr) : 0;

            JsonObject meta = getUserMetadata();
            long cloudTs = 0;
            if (meta != null && meta.has("last_backup_timestamp") && !meta.get("last_backup_timestamp").isJsonNull()) {
                cloudTs = meta.get("last_backup_timestamp").getAsLong();
            }

            boolean isStaleDevice = cloudTs > localVersionTs;

            // PUSH FIRST: Ensure all local unsynced edits reach the cloud before pulling
            try {
                pushPendingChangesInternal(db, true);
            } catch (Exception pushEx) {
                System.err.println("SYNC: Pre-pull push warning: " + pushEx.getMessage());
            }

            if (isManual) {
                notifyStatus("Downloading Updates...");
            }

            // PULL STOCK (Full Sync for stock to handle physical deletions easily since stock is small)
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/stock"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .GET().build();
            boolean stockPulled = false;
            HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(res.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    boolean acceptPieces = true; // Always accept mobile & cloud stock updates in background sync
                    db.upsertCloudStock(arr, acceptPieces);
                    stockPulled = true;
                }
            }

            // PULL SALES (Full Sync for sales to handle physical deletions easily across devices)
            String salesUrl = REST_URL + "/sales";
            req = HttpRequest.newBuilder()
                    .uri(URI.create(salesUrl))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .GET().build();
            boolean salesPulled = false;
            res = client.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(res.body()).getAsJsonArray();
                db.upsertCloudSales(arr, false); // false = Full Sync
                salesPulled = true;
            }

            // Pull receipt settings from cloud
            downloadReceiptSettings();

            // If device was stale, now that we've pulled down the latest cloud data, push any remaining legitimate local edits
            if (isStaleDevice) {
                try {
                    pushPendingChangesInternal(db, true);
                } catch (Exception pushEx) {
                    System.err.println("SYNC: Post-pull push warning: " + pushEx.getMessage());
                }
            }

            boolean anyPulled = stockPulled || salesPulled;
            if (cloudTs > localVersionTs) {
                db.saveSetting("last_backup_timestamp", String.valueOf(cloudTs));
                notifyStatus("Cloud: Integrated");
                return true;
            } else if (anyPulled) {
                notifyStatus("Cloud: Updated");
                return true;
            } else {
                notifyStatus("Cloud: Synced");
                return false;
            }
        } catch (IOException e) {
            if (e.getMessage() != null && e.getMessage().contains("401")) {
                System.out.println("SYNC: Token expired (401), attempting to refresh session and retry...");
                boolean refreshed = false;
                try {
                    if (currentRefreshToken != null) {
                        refreshed = signInWithRefreshToken(currentRefreshToken);
                    }
                } catch (Exception refreshEx) {
                    System.err.println("SYNC: Token refresh failed: " + refreshEx.getMessage());
                }
                // Retry the sync once with the new token
                if (refreshed) {
                    try {
                        syncLock.unlock(); // Release before recursive call (it re-acquires)
                        return syncOnLogin(dbPath, localHasData, isManual);
                    } catch (Exception retryEx) {
                        System.err.println("SYNC: Retry after token refresh failed: " + retryEx.getMessage());
                        // Re-acquire lock so finally block can release it
                        syncLock.tryLock();
                    }
                }
            } else {
                e.printStackTrace();
            }
            notifyStatus("Cloud: Error");
            return false;
        } catch (Exception e) {
            e.printStackTrace();
            notifyStatus("Cloud: Error");
            return false;
        } finally {
            syncLock.unlock();
        }
    }


    // --- ADMIN ---

    public JsonObject getAllUsers() throws IOException, InterruptedException {
        if (currentUserId == null)
            throw new IOException("Not logged in");

        // GET /rest/v1/users?select=*
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/users?select=*"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", getValidBearerToken())
                .GET()
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        System.out.println("DEBUG: getAllUsers status=" + response.statusCode());
        System.out.println("DEBUG: getAllUsers body=" + response.body());

        if (response.statusCode() == 200) {
            JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
            JsonObject result = new JsonObject();
            // Convert array to map for AdminDashboard compatibility
            // Map<UID, UserObj>
            for (JsonElement elem : arr) {
                JsonObject u = elem.getAsJsonObject();
                if (u.has("id")) {
                    result.add(u.get("id").getAsString(), u);
                }
            }
            return result;
        }
        throw new IOException("Failed to list users: " + response.statusCode() + " " + response.body());
    }

    public void adminUpdateUser(String targetUid, Map<String, Object> updates)
            throws IOException, InterruptedException {
        // PATCH /rest/v1/users?id=eq.targetUid
        JsonObject json = new JsonObject();
        updates.forEach((k, v) -> {
            if (v instanceof String)
                json.addProperty(k, (String) v);
            else if (v instanceof Boolean)
                json.addProperty(k, (Boolean) v);
            else if (v instanceof Number)
                json.addProperty(k, (Number) v);
        });

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/users?id=eq." + targetUid))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", getValidBearerToken())
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                .build();

        client.send(request, HttpResponse.BodyHandlers.ofString());
    }

    public String getCurrentUserId() {
        return currentUserId;
    }

    public String getCurrentRefreshToken() {
        return currentRefreshToken;
    }

    public boolean isLoggedIn() {
        return currentUserId != null;
    }

    // --- PUSH-TO-LOGIN ---

    public String createLoginRequest(String email) throws IOException, InterruptedException {
        // Purge any stale pending login requests for this email first
        try {
            String encodedEmail = java.net.URLEncoder.encode(email, java.nio.charset.StandardCharsets.UTF_8);
            HttpRequest deleteOld = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/login_requests?email=eq." + encodedEmail + "&status=eq.pending"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + SUPABASE_KEY)
                    .DELETE()
                    .build();
            client.send(deleteOld, HttpResponse.BodyHandlers.ofString());
        } catch (Exception ignored) {}

        JsonObject row = new JsonObject();
        row.addProperty("email", email);
        row.addProperty("status", "pending");

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/login_requests"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + SUPABASE_KEY) // Use anon key for insertion if RLS allows
                .header("Content-Type", "application/json")
                .header("Prefer", "return=representation")
                .POST(HttpRequest.BodyPublishers.ofString(row.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 201) {
            JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
            return arr.get(0).getAsJsonObject().get("id").getAsString();
        } else {
            throw new IOException("Failed to create login request: " + response.body());
        }
    }

    public JsonObject pollLoginRequest(String requestId) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/login_requests?id=eq." + requestId + "&select=*"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + SUPABASE_KEY)
                .GET()
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
            if (arr.size() > 0) {
                return arr.get(0).getAsJsonObject();
            }
        }
        return null;
    }

    public void deleteLoginRequest(String requestId) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/login_requests?id=eq." + requestId))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + SUPABASE_KEY)
                    .DELETE()
                    .build();
            client.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public String fetchLatestReleaseInfo(String platform) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/app_releases?platform=eq." + platform + "&order=created_at.desc&limit=1"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + SUPABASE_KEY)
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    return arr.get(0).getAsJsonObject().toString();
                }
            }
        } catch (Exception e) {
            System.err.println("SupabaseService: Error fetching release info: " + e.getMessage());
        }
        return null;
    }

    /**
     * Result of a sync batch RPC call.
     * Allows callers to distinguish auth failures from server errors.
     */
    public enum SyncResult {
        SUCCESS,          // 200/201 — batch processed
        AUTH_EXPIRED,     // 401 — token needs refresh
        SERVER_ERROR,     // 5xx, 429, 408 — retryable with backoff
        CLIENT_ERROR,     // 4xx (not 401) — likely permanent, needs human review
        NETWORK_ERROR,    // IOException — connectivity issue
        NOT_AUTHENTICATED // No tokens available
    }

    public SyncResult processPowerSyncBatchRPC(String deviceId, JsonArray operations) {
        if (currentUserId == null || currentAccessToken == null) {
            return SyncResult.NOT_AUTHENTICATED;
        }
        try {
            JsonObject body = new JsonObject();
            body.addProperty("p_device_id", deviceId);
            body.addProperty("p_user_id", currentUserId);
            body.add("p_operations", operations);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/rpc/rpc_process_sync_batch"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", getValidBearerToken())
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body.toString()))
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            // Server-Client Clock Sync: Calculate server time offset
            if (response.headers().firstValue("Date").isPresent()) {
                try {
                    String dateStr = response.headers().firstValue("Date").get();
                    java.time.Instant serverInstant = java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME.parse(dateStr, java.time.Instant::from);
                    com.meto.inventory.powersync.ClockSync.updateClockOffset(serverInstant.toEpochMilli());
                } catch (Exception ignored) {}
            }

            int statusCode = response.statusCode();
            if (statusCode == 200 || statusCode == 201) {
                return SyncResult.SUCCESS;
            } else if (statusCode == 401) {
                System.err.println("PowerSync RPC: 401 - token expired");
                return SyncResult.AUTH_EXPIRED;
            } else if (statusCode >= 500 || statusCode == 429 || statusCode == 408) {
                System.err.println("PowerSync RPC: Server error " + statusCode + " - " + response.body());
                return SyncResult.SERVER_ERROR;
            } else {
                System.err.println("PowerSync RPC: Client error " + statusCode + " - " + response.body());
                return SyncResult.CLIENT_ERROR;
            }
        } catch (java.io.IOException e) {
            System.err.println("PowerSync RPC Network Error: " + e.getMessage());
            return SyncResult.NETWORK_ERROR;
        } catch (Exception e) {
            System.err.println("PowerSync RPC Error: " + e.getMessage());
            return SyncResult.NETWORK_ERROR;
        }
    }
}


