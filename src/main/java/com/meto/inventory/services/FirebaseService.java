package com.meto.inventory.services;

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

public class FirebaseService {
    // TODO: REPLACE WITH YOUR ACTUAL API KEY
    private static final String API_KEY = "AIzaSyAYHuQxl09oN-BrclKZXmGHujhyotGimLw";
    // TODO: REPLACE WITH YOUR ACTUAL DATABASE URL
    private static final String DATABASE_URL = "https://managementsys-3191c-default-rtdb.europe-west1.firebasedatabase.app";

    private static final String AUTH_URL = "https://identitytoolkit.googleapis.com/v1/accounts";

    private static FirebaseService instance;
    private final HttpClient client;
    private String currentIdToken;
    private String currentUserId;
    private java.util.List<java.util.function.Consumer<String>> statusListeners = new java.util.ArrayList<>();

    private FirebaseService() {
        this.client = HttpClient.newHttpClient();
    }

    public static FirebaseService getInstance() {
        if (instance == null) {
            instance = new FirebaseService();
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

    public boolean signUp(String email, String password) throws IOException, InterruptedException {
        return performAuthAction(email, password, ":signUp");
    }

    public boolean signIn(String email, String password) throws IOException, InterruptedException {
        return performAuthAction(email, password, ":signInWithPassword");
    }

    private boolean performAuthAction(String email, String password, String endpoint)
            throws IOException, InterruptedException {
        JsonObject payload = new JsonObject();
        payload.addProperty("email", email);
        payload.addProperty("password", password);
        payload.addProperty("returnSecureToken", true);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(AUTH_URL + endpoint + "?key=" + API_KEY))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString()))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 200) {
            JsonObject json = JsonParser.parseString(response.body()).getAsJsonObject();
            this.currentUserId = json.get("localId").getAsString();
            this.currentIdToken = json.get("idToken").getAsString();
            return true;
        } else {
            String errorMessage = "Authentication failed";
            try {
                JsonObject json = JsonParser.parseString(response.body()).getAsJsonObject();
                if (json.has("error")) {
                    JsonObject errorObj = json.getAsJsonObject("error");
                    if (errorObj.has("message")) {
                        errorMessage = errorObj.get("message").getAsString();
                    }
                }
            } catch (Exception e) {
                errorMessage += ": " + response.body();
            }
            System.err.println("Auth Error: " + response.body());
            throw new IOException(errorMessage);
        }
    }

    public boolean uploadDatabase(String filePath) {
        if (currentUserId == null || currentIdToken == null) {
            System.err.println("Cannot upload: User not logged in.");
            return false;
        }

        File file = new File(filePath);
        if (!file.exists()) {
            System.err.println("Database file not found: " + filePath);
            return false;
        }

        try {
            notifyStatus("Syncing...");

            // Read file and encode to Base64
            byte[] fileBytes = Files.readAllBytes(file.toPath());
            String base64Content = java.util.Base64.getEncoder().encodeToString(fileBytes);

            // Create JSON payload
            JsonObject payload = new JsonObject();
            payload.addProperty("db_file", base64Content);
            payload.addProperty("timestamp", System.currentTimeMillis());

            // Realtime DB URL: /users/{userId}.json
            // Append .json?auth=TOKEN
            String putUrl = DATABASE_URL + "/users/" + currentUserId + ".json?auth=" + currentIdToken;

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(putUrl))
                    .header("Content-Type", "application/json")
                    .PUT(HttpRequest.BodyPublishers.ofString(payload.toString()))
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                System.out.println("Backup successful to Realtime DB.");
                notifyStatus("Cloud: Synced");
                return true;
            } else {
                System.err.println("Upload Failed: (" + response.statusCode() + ") " + response.body());
                if (response.statusCode() == 404 || response.statusCode() == 401) {
                    System.err.println("Check DATABASE_URL in FirebaseService.java and Realtime Database Rules.");
                }
                notifyStatus("Cloud: Error");
                return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            notifyStatus("Cloud: Offline");
            return false;
        }
    }

    public boolean syncOnLogin(String dbPath) {
        if (currentUserId == null || currentIdToken == null)
            return false;

        try {
            // Realtime DB URL: /users/{userId}.json
            String getUrl = DATABASE_URL + "/users/" + currentUserId + ".json?auth=" + currentIdToken;

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(getUrl))
                    .GET()
                    .build();

            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                String body = response.body();
                // Handle null/empty response (New User)
                if (body == null || body.trim().equals("null")) {
                    System.out.println("No cloud data found. Uploading local if exists.");
                    File local = new File(dbPath);
                    if (local.exists()) {
                        uploadDatabase(dbPath);
                    }
                    return false; // Kept local
                }

                // Parse JSON response
                JsonObject json = JsonParser.parseString(body).getAsJsonObject();
                if (json != null && json.has("db_file")) {
                    long cloudTimestamp = 0;
                    if (json.has("timestamp")) {
                        cloudTimestamp = json.get("timestamp").getAsLong();
                    }

                    File localFile = new File(dbPath);
                    long localTimestamp = localFile.exists() ? localFile.lastModified() : 0;

                    // Sync Logic
                    if (cloudTimestamp > localTimestamp) {
                        System.out.println("Cloud is newer. Downloading...");
                        String base64Content = json.get("db_file").getAsString();
                        byte[] fileBytes = java.util.Base64.getDecoder().decode(base64Content);
                        Files.write(Path.of(dbPath), fileBytes);
                        System.out.println("Restored from Cloud.");
                        return true; // Overwritten
                    } else {
                        System.out.println("Local is newer or same. Uploading to sync...");
                        uploadDatabase(dbPath);
                        return false; // Kept local
                    }
                } else {
                    return false; // No data found
                }
            } else {
                if (response.statusCode() != 404) {
                    System.err.println("Sync Failed: " + response.statusCode());
                }
                return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public String getCurrentUserId() {
        return currentUserId;
    }

    public boolean isLoggedIn() {
        return currentUserId != null;
    }
}
