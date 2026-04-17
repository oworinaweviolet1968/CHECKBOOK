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
    private String currentAccessToken;
    private String currentRefreshToken;
    private String currentUserId;
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

    private void notifyStatus(String status) {
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

            // However, we DO want to ensure the metadata row exists immediately
            // But we can't easily get the new User ID without parsing the response.
            // And even if we parse it, we can't insert into public.users AS THE ADMIN for
            // the NEW USER
            // unless we have RLS policies allowing Admin to INSERT for others.
            // We added "Admins can view/update all data" but not INSERT.
            // Let's rely on the user's first login to trigger ensureUserMetadataExists
            // OR add the INSERT policy.

            // For now, simple return true.
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
                String encryptedToken = encrypt(currentRefreshToken);
                Files.writeString(Path.of(resolvePath("user_session.txt")), encryptedToken);
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
                // If it looks like a clear-text token (not base64 or too short), we might skip
                // but decrypt will just fail.
                try {
                    return decrypt(content);
                } catch (Exception e) {
                    // Decryption failed - could be old plain-text session or moved disk
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
        if (currentUserId == null)
            return false;

        File file = new File(filePath);
        if (!file.exists())
            return false;

        try {
            notifyStatus("Uploading...");
            // CHANGE: Use the actual filename (inventory_UID.db) instead of generic
            // inventory.db
            String cloudFileName = file.getName();
            String path = "backups/" + currentUserId + "/" + cloudFileName;

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(STORAGE_URL + "/" + path))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .header("Content-Type", "application/x-sqlite3")
                    .header("x-upsert", "true") // Overwrite
                    .POST(HttpRequest.BodyPublishers.ofFile(file.toPath()))
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                // Save timestamp and file URL to DB
                Map<String, Object> updates = new HashMap<>();
                updates.put("last_backup_timestamp", System.currentTimeMillis());
                updateUserFields(updates);

                notifyStatus("Cloud: Synced");
                return true;
            } else {
                System.err.println("Upload failed: " + response.body());
                notifyStatus("Cloud: Error");
                return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            notifyStatus("Cloud: Offline");
            return false;
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
        if (currentUserId == null)
            return false;

        try {
            // Check metadata first to see if cloud is newer
            JsonObject meta = getUserMetadata();
            long cloudTs = 0;
            if (meta.has("last_backup_timestamp") && !meta.get("last_backup_timestamp").isJsonNull()) {
                cloudTs = meta.get("last_backup_timestamp").getAsLong();
            }

            File local = new File(dbPath);
            long localTs = local.exists() ? local.lastModified() : 0;

            System.out.println("SYNC DEBUG: CloudTS=" + cloudTs + ", LocalTS=" + localTs);
            System.out.println("SYNC DEBUG: LocalHasData=" + localHasData + ", LocalFileExists=" + local.exists());

            // Derive cloud path from local filename
            String cloudFileName = local.getName();

            // Note: If cloudTs == 0 (fresh account), this block is skipped.
            if (cloudTs > localTs) {
                System.out.println("Cloud is newer. Downloading...");
                notifyStatus("Downloading...");
                return downloadWithProgress(cloudFileName, dbPath);

            } else if (isManual || cloudTs == 0) {
                // Upload only if manual refresh or if cloud is totally empty
                System.out.println("Local newer or manual trigger. Checking if upload needed...");

                if (localHasData) {
                    System.out.println("Uploading changes...");
                    uploadDatabase(dbPath);
                } else if (cloudTs > 0 && isManual) {
                    System.out.println("Force restoring from cloud (manual)...");
                    return downloadWithProgress(cloudFileName, dbPath);
                }
            } else {
                System.out.println("Auto-sync: Local is newer or same, skipping auto-upload to avoid stalls.");
                notifyStatus("Cloud: Integrated");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    private boolean downloadWithProgress(String cloudFileName, String localPath) {
        try {
            String path = "backups/" + currentUserId + "/" + cloudFileName;
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(STORAGE_URL + "/" + path))
                    .header("apikey", SUPABASE_KEY)
                    .header("Authorization", "Bearer " + currentAccessToken)
                    .GET()
                    .build();

            HttpResponse<java.io.InputStream> response = client.send(request,
                    HttpResponse.BodyHandlers.ofInputStream());

            if (response.statusCode() == 200) {
                long totalBytes = response.headers().firstValueAsLong("Content-Length").orElse(-1L);
                System.out.println("Downloading... Total Bytes: " + totalBytes);

                try (java.io.InputStream is = response.body();
                        java.io.FileOutputStream fos = new java.io.FileOutputStream(localPath)) {

                    byte[] buffer = new byte[8192];
                    int bytesRead;
                    long totalRead = 0;

                    while ((bytesRead = is.read(buffer)) != -1) {
                        fos.write(buffer, 0, bytesRead);
                        totalRead += bytesRead;
                        if (totalBytes > 0) {
                            notifyProgress((double) totalRead / totalBytes);
                        }
                    }
                }

                notifyProgress(1.0); // Complete
                long newSize = Files.size(Path.of(localPath));
                System.out.println("Restored from Supabase. Size=" + newSize);
                return true;
            } else {
                System.err.println("Download failed: " + response.statusCode());

                // FAILSAFE FOR LEGACY FILENAME (Only on FORCE download, but let's keep it
                // simple here)
                if (response.statusCode() == 404 && !cloudFileName.equals("inventory.db")) {
                    System.out.println("Retrying with legacy 'inventory.db'...");
                    return downloadWithProgress("inventory.db", localPath);
                }

                return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
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
