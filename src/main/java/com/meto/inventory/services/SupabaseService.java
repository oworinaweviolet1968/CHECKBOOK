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
    private static final String SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8";

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
            String body = response.body().toLowerCase();
            if (response.statusCode() == 400 && (body.contains("invalid_grant") || body.contains("invalid refresh token") || body.contains("refresh_token_not_found") || body.contains("already used"))) {
                System.err.println("Refresh token explicitly invalid. Clearing local session.");
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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

    public String loadSession() {
        try {
            Path path = Path.of(resolvePath("user_session.txt"));
            if (Files.exists(path)) {
                String content = Files.readString(path).trim();
                try {
                    String decrypted = decrypt(content);
                    if (decrypted.startsWith("{") && decrypted.endsWith("}")) {
                        JsonObject json = JsonParser.parseString(decrypted).getAsJsonObject();
                        if (json.has("user_id")) {
                            this.currentUserId = json.get("user_id").getAsString();
                        }
                        if (json.has("refresh_token")) {
                            return json.get("refresh_token").getAsString();
                        }
                    }
                    return decrypted;
                } catch (Exception e) {
                    System.err.println("Session decryption failed. Likely old or insecure session.");
                    return null; 
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }

    private void clearSession() {
        try {
            Files.deleteIfExists(Path.of(resolvePath("user_session.txt")));
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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

        // GET /rest/v1/users?id=eq.UID&select=*
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/users?id=eq." + currentUserId + "&select=*"))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + currentAccessToken)
                .GET()
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            JsonArray arr = JsonParser.parseString(response.body()).getAsJsonArray();
            if (arr.size() > 0)
                return arr.get(0).getAsJsonObject();
            return new JsonObject(); // Metadata missing
        } else {
            throw new IOException("Failed to fetch metadata: " + response.statusCode());
        }
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

        // PATCH /rest/v1/users?id=eq.UID
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(REST_URL + "/users?id=eq." + currentUserId))
                .header("apikey", SUPABASE_KEY)
                .header("Authorization", "Bearer " + currentAccessToken)
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() > 299) {
            throw new IOException("Update failed: " + response.statusCode());
        }
    }

    /**
     * Lightweight heartbeat — PATCHes desktop_last_seen (epoch ms) to the users table.
     * Called every 10s by the AutoSync thread. Does NOT hold the sync lock.
     */
    public void updateHeartbeat() {
        if (currentUserId == null || currentAccessToken == null) return;
        try {
            long now = System.currentTimeMillis();
            JsonObject json = new JsonObject();
            json.addProperty("desktop_last_seen", now);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/users?id=eq." + currentUserId))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .header("Content-Type", "application/json")
                    .timeout(java.time.Duration.ofSeconds(5))
                    .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                    .build();

            client.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (Exception e) {
            // Silent — heartbeat is best-effort
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
                System.out.println("SYNC: Token expired (401), attempting to refresh session in background...");
                try {
                    if (currentRefreshToken != null) {
                        signInWithRefreshToken(currentRefreshToken);
                    }
                } catch (Exception ignored) {}
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
        // STOCK
        boolean stockUploadSuccess = true;
        if (dirtyStock.size() > 0) {
            String nowIso = java.time.Instant.now().toString();
            for (JsonElement el : dirtyStock) {
                JsonObject o = el.getAsJsonObject();
                o.addProperty("user_id", currentUserId);
                o.addProperty("updated_at", nowIso);
            }
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/stock?on_conflict=sync_id"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=merge-duplicates")
                    .POST(HttpRequest.BodyPublishers.ofString(dirtyStock.toString()))
                    .build();
            HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
            System.out.println("STOCK UPLOAD RESPONSE: " + res.statusCode() + " " + res.body());
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
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .header("Content-Type", "application/json")
                    .header("Prefer", "resolution=merge-duplicates")
                    .POST(HttpRequest.BodyPublishers.ofString(dirtySales.toString()))
                    .build();
            HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
            System.out.println("SALES UPLOAD RESPONSE: " + res.statusCode() + " " + res.body());
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
                            .header("Authorization", "Bearer " + currentAccessToken)
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
                if (item != null && quantity != null) {
                    HttpRequest req = HttpRequest.newBuilder()
                            .uri(URI.create(REST_URL + "/stock?item=eq." + java.net.URLEncoder.encode(item, java.nio.charset.StandardCharsets.UTF_8) + "&quantity=eq." + java.net.URLEncoder.encode(quantity, java.nio.charset.StandardCharsets.UTF_8)))
                            .header("apikey", SUPABASE_KEY)
                            .header("Authorization", "Bearer " + currentAccessToken)
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
                            .header("Authorization", "Bearer " + currentAccessToken)
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
                            .header("Authorization", "Bearer " + currentAccessToken)
                            .DELETE().build();
                    client.send(req, HttpResponse.BodyHandlers.ofString());
                }
            }
        }

        if (stockUploadSuccess && salesUploadSuccess) {
            db.clearDirtyFlags();
            lastSyncFailed = false;
        } else {
            lastSyncFailed = true;
            System.err.println("SYNC: Preserving dirty flags because cloud POST upload returned non-2xx status code.");
        }
        lastSyncFailed = false;

        // Update timestamp
        long ts = System.currentTimeMillis();
        Map<String, Object> updates = new HashMap<>();
        updates.put("last_backup_timestamp", ts);
        updateUserFields(updates);
        db.saveSetting("last_backup_timestamp", String.valueOf(ts));
        notifyStatus("Cloud: " + new java.util.Date(ts).toString());

        return true;
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
                    .header("Authorization", "Bearer " + currentAccessToken)
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
                System.out.println("SYNC: Token expired (401), attempting to refresh session in background...");
                try {
                    if (currentRefreshToken != null) {
                        signInWithRefreshToken(currentRefreshToken);
                    }
                } catch (Exception ignored) {}
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
                .header("Authorization", "Bearer " + currentAccessToken)
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
                .header("Authorization", "Bearer " + currentAccessToken)
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(json.toString()))
                .build();

        client.send(request, HttpResponse.BodyHandlers.ofString());
    }

    public String getCurrentUserId() {
        return currentUserId;
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

    public boolean processPowerSyncBatchRPC(String deviceId, JsonArray operations) {
        if (currentUserId == null || currentAccessToken == null) {
            return false;
        }
        try {
            JsonObject body = new JsonObject();
            body.addProperty("p_device_id", deviceId);
            body.addProperty("p_user_id", currentUserId);
            body.add("p_operations", operations);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(REST_URL + "/rpc/rpc_process_sync_batch"))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
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

            return response.statusCode() == 200 || response.statusCode() == 201;
        } catch (Exception e) {
            System.err.println("PowerSync RPC Error: " + e.getMessage());
            return false;
        }
    }
}


