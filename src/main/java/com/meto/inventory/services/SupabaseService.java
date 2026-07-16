package com.meto.inventory.services;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.ArrayList;
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
    private long lastKnownCloudTimestamp = 0;
    private long lastFetchCloudTs = 0; 
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

    public static SupabaseService getInstance() {
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
            
            // Check for changes
            JsonArray dirtyStock = db.getDirtyStock();
            JsonArray dirtySales = db.getDirtySales();
            JsonArray delStock = db.getDirtyDeletedStock();
            JsonArray delSales = db.getDirtyDeletedHistory();

            boolean hasChanges = dirtyStock.size() > 0 || dirtySales.size() > 0 || delStock.size() > 0 || delSales.size() > 0;
            if (!hasChanges) {
                return true; // Silent success, no need to trigger UI or push empty updates
            }

            if (!isSilent) {
                notifyStatus("Syncing with Postgres...");
            }
            
            // --- 1. PUSH ---
            // STOCK
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
            }
            
            // SALES
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
            }

            // DELETIONS
            if (delStock.size() > 0) {
                List<String> ids = new ArrayList<>();
                for (JsonElement el : delStock) ids.add(el.getAsJsonObject().get("sync_id").getAsString());
                HttpRequest req = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/stock?sync_id=in.(" + String.join(",", ids) + ")"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + currentAccessToken)
                        .DELETE().build();
                client.send(req, HttpResponse.BodyHandlers.ofString());
            }

            if (delSales.size() > 0) {
                List<String> ids = new ArrayList<>();
                for (JsonElement el : delSales) ids.add(el.getAsJsonObject().get("sync_id").getAsString());
                HttpRequest req = HttpRequest.newBuilder()
                        .uri(URI.create(REST_URL + "/sales?sync_id=in.(" + String.join(",", ids) + ")"))
                        .header("apikey", SUPABASE_KEY)
                        .header("Authorization", "Bearer " + currentAccessToken)
                        .DELETE().build();
                client.send(req, HttpResponse.BodyHandlers.ofString());
            }

            db.clearDirtyFlags();
            lastSyncFailed = false;

            // Update timestamp
            long ts = System.currentTimeMillis();
            Map<String, Object> updates = new HashMap<>();
            updates.put("last_backup_timestamp", ts);
            updateUserFields(updates);
            db.saveSetting("last_backup_timestamp", String.valueOf(ts));
            lastKnownCloudTimestamp = ts;
            notifyStatus("Cloud: " + new java.util.Date(ts).toString());

            return true;
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
        } catch (Exception e) {
            System.err.println("Failed to upload receipt settings: " + e.getMessage());
        }
    }

    /**
     * Downloads receipt settings from Supabase Storage and saves them locally.
     * Called during syncOnLogin to ensure desktop has the latest receipt info.
     */
    public void downloadReceiptSettings() {
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
                    String[] keys = {"receipt_shop_name", "receipt_shop_number", "receipt_location", "receipt_phone", "receipt_phone2"};
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

    private void notifyProgress(double progress) {
        javafx.application.Platform.runLater(() -> {
            for (var listener : progressListeners) {
                listener.accept(progress);
            }
        });
    }

    public boolean syncOnLogin(String dbPath, boolean localHasData, boolean isManual) {
        if (!syncLock.tryLock()) return false;
        try {
            if (currentUserId == null) return false;

            String localVersionStr = com.meto.inventory.DataManager.getInstance().getDbHelper().getSetting("last_backup_timestamp");
            long localVersionTs = (localVersionStr != null) ? Long.parseLong(localVersionStr) : 0;
            long queryTs = localVersionTs > 300000 ? localVersionTs - 300000 : 0;
            String isoTimestamp = java.time.Instant.ofEpochMilli(queryTs).toString();

            if (isManual) {
                notifyStatus("Downloading Updates...");
            }
            com.meto.inventory.DatabaseHelper db = com.meto.inventory.DataManager.getInstance().getDbHelper();

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
                    boolean acceptPieces = isManual || localVersionTs == 0;
                    db.upsertCloudStock(arr, acceptPieces);
                    stockPulled = true;
                }
            }

            // PULL SALES (Incremental, or Full if manual refresh)
            String salesUrl = REST_URL + "/sales";
            if (!isManual) {
                salesUrl += "?updated_at=gt." + isoTimestamp;
            }
            req = HttpRequest.newBuilder()
                    .uri(URI.create(salesUrl))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .GET().build();
            boolean salesPulled = false;
            res = client.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 200) {
                JsonArray arr = JsonParser.parseString(res.body()).getAsJsonArray();
                if (arr.size() > 0) {
                    boolean isIncremental = localVersionTs > 0;
                    db.upsertCloudSales(arr, isIncremental);
                    salesPulled = true;
                }
            }

            // Check if cloud timestamp increased
            JsonObject meta = getUserMetadata();
            long cloudTs = 0;
            if (meta.has("last_backup_timestamp") && !meta.get("last_backup_timestamp").isJsonNull()) {
                cloudTs = meta.get("last_backup_timestamp").getAsLong();
            }

            // Pull receipt settings from cloud
            downloadReceiptSettings();

            boolean anyPulled = stockPulled || salesPulled;
            if (cloudTs > localVersionTs) {
                db.saveSetting("last_backup_timestamp", String.valueOf(cloudTs));
                this.lastKnownCloudTimestamp = cloudTs;
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
}
