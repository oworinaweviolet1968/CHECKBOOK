package com.meto.inventory.services;

import javafx.application.Platform;
import javafx.scene.control.Alert;
import javafx.scene.control.ButtonBar;
import javafx.scene.control.ButtonType;
import javafx.scene.control.ProgressIndicator;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.meto.inventory.DatabaseHelper;
import com.meto.inventory.DataManager;

/**
 * Free & Open-Source Auto-Updater for CheckBook IMS JavaFX Desktop App.
 * Checks Supabase for new app releases and downloads/launches updates seamlessly.
 */
public class AutoUpdater {

    public static final String CURRENT_VERSION = "2.2.0";

    /**
     * Checks for updates asynchronously on app startup.
     */
    public static void checkForUpdatesAsync() {
        new Thread(() -> {
            try {
                // Fetch release information from Supabase REST API
                SupabaseService service = SupabaseService.getInstance();
                String responseJson = service.fetchLatestReleaseInfo("desktop");

                if (responseJson == null || responseJson.isEmpty()) {
                    return;
                }

                JsonObject release = JsonParser.parseString(responseJson).getAsJsonObject();
                if (!release.has("version") || !release.has("download_url")) {
                    return;
                }

                String latestVersion = release.get("version").getAsString();
                String downloadUrl = release.get("download_url").getAsString();
                boolean mandatory = release.has("mandatory") && release.get("mandatory").getAsBoolean();
                String releaseNotes = release.has("release_notes") ? release.get("release_notes").getAsString() : "";

                DatabaseHelper db = DataManager.getInstance().getDbHelper();
                String installedVer = (db != null) ? db.getSetting("installed_version") : null;

                String effectiveCurrent = (installedVer != null && isVersionNewer(CURRENT_VERSION, installedVer))
                        ? installedVer : CURRENT_VERSION;

                // Behaviour 2: Prompts on launch whenever a newer version is available
                if (isVersionNewer(effectiveCurrent, latestVersion)) {
                    Platform.runLater(() -> promptUserToUpdate(latestVersion, downloadUrl, mandatory, releaseNotes));
                }
            } catch (Exception e) {
                System.err.println("AutoUpdater: Version check skipped due to error: " + e.getMessage());
            }
        }).start();
    }

    /**
     * Compares semver version strings (e.g., "2.2.0" vs "2.3.0").
     */
    public static boolean isVersionNewer(String currentVer, String latestVer) {
        if (currentVer == null || latestVer == null) return false;
        String[] currentParts = currentVer.split("\\.");
        String[] latestParts = latestVer.split("\\.");

        int length = Math.max(currentParts.length, latestParts.length);
        for (int i = 0; i < length; i++) {
            int currentNum = i < currentParts.length ? Integer.parseInt(currentParts[i].replaceAll("[^0-9]", "")) : 0;
            int latestNum = i < latestParts.length ? Integer.parseInt(latestParts[i].replaceAll("[^0-9]", "")) : 0;

            if (latestNum > currentNum) return true;
            if (latestNum < currentNum) return false;
        }
        return false;
    }

    private static void promptUserToUpdate(String newVersion, String downloadUrl, boolean mandatory, String releaseNotes) {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle("New Update Available");
        alert.setHeaderText("CheckBook IMS Version " + newVersion + " is available!");

        VBox content = new VBox(10);
        Text msg = new Text("A new version of CheckBook IMS is ready to install.\nInstalled version: " + CURRENT_VERSION);
        content.getChildren().add(msg);

        if (!releaseNotes.isEmpty()) {
            Text notes = new Text("What's New:\n" + releaseNotes);
            notes.setStyle("-fx-font-style: italic; -fx-fill: #555555;");
            content.getChildren().add(notes);
        }

        alert.getDialogPane().setContent(content);

        ButtonType updateBtn = new ButtonType("Update Now", ButtonBar.ButtonData.OK_DONE);
        ButtonType skipBtn = new ButtonType("Later", ButtonBar.ButtonData.CANCEL_CLOSE);

        if (mandatory) {
            alert.getButtonTypes().setAll(updateBtn);
        } else {
            alert.getButtonTypes().setAll(updateBtn, skipBtn);
        }

        alert.showAndWait().ifPresent(response -> {
            if (response == updateBtn) {
                DatabaseHelper db = DataManager.getInstance().getDbHelper();
                if (db != null) {
                    try { db.saveSetting("installed_version", newVersion); } catch (Exception ignored) {}
                }
                downloadAndInstallUpdate(downloadUrl);
            }
            // "Later": closes the prompt for this launch, but will prompt again on next app launch
        });
    }

    private static void downloadAndInstallUpdate(String downloadUrl) {
        Alert progressAlert = new Alert(Alert.AlertType.NONE);
        progressAlert.setTitle("Downloading Update");
        progressAlert.setHeaderText("Downloading CheckBook IMS installer...");
        
        ProgressIndicator progress = new ProgressIndicator(-1);
        VBox vbox = new VBox(15, progress, new Text("Please wait, preparing setup..."));
        vbox.setStyle("-fx-alignment: center; -fx-padding: 20;");
        progressAlert.getDialogPane().setContent(vbox);
        progressAlert.show();

        new Thread(() -> {
            try {
                URL url = new URL(downloadUrl);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(30000);

                String fileName = downloadUrl.endsWith(".msi") ? "CheckBook_Installer.msi" : "CheckBook_Installer.exe";
                File tempFile = new File(System.getProperty("java.io.tmpdir"), fileName);

                try (InputStream in = new BufferedInputStream(conn.getInputStream());
                     FileOutputStream out = new FileOutputStream(tempFile)) {
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = in.read(buffer)) != -1) {
                        out.write(buffer, 0, count);
                    }
                }

                Platform.runLater(() -> {
                    progressAlert.close();
                    launchInstallerAndExit(tempFile);
                });

            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> {
                    progressAlert.close();
                    Alert err = new Alert(Alert.AlertType.ERROR);
                    err.setTitle("Update Failed");
                    err.setHeaderText("Could not download the update.");
                    err.setContentText("Error: " + e.getMessage() + "\nPlease try downloading directly from the website.");
                    err.show();
                });
            }
        }).start();
    }

    private static void launchInstallerAndExit(File installerFile) {
        try {
            String os = System.getProperty("os.name").toLowerCase();
            ProcessBuilder pb;

            if (os.contains("win")) {
                if (installerFile.getName().endsWith(".msi")) {
                    pb = new ProcessBuilder("msiexec", "/i", installerFile.getAbsolutePath(), "/passive");
                } else {
                    pb = new ProcessBuilder(installerFile.getAbsolutePath());
                }
            } else if (os.contains("mac")) {
                pb = new ProcessBuilder("open", installerFile.getAbsolutePath());
            } else {
                pb = new ProcessBuilder("xdg-open", installerFile.getAbsolutePath());
            }

            pb.start();
            System.exit(0);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
