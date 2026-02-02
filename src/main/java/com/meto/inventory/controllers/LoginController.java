package com.meto.inventory.controllers;

import com.meto.inventory.services.SupabaseService;
import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.TextField;
import javafx.stage.Stage;

import java.io.IOException;

public class LoginController {

    @FXML
    private TextField emailField;
    @FXML
    private PasswordField passwordField;
    @FXML
    private Button loginButton;
    @FXML
    private Label statusLabel;

    @FXML
    public void initialize() {
        loginButton.setOnAction(e -> handleLogin());
    }

    private void handleLogin() {
        String email = emailField.getText().trim();
        String password = passwordField.getText();

        if (email.isEmpty() || password.isEmpty()) {
            statusLabel.setText("Please enter both email and password.");
            return;
        }

        setLoading(true);

        new Thread(() -> {
            try {
                SupabaseService service = SupabaseService.getInstance();
                boolean success = service.signIn(email, password);

                if (success) {
                    // Check for Admin
                    if (email.equalsIgnoreCase("admin@gmail.com")) {
                        Platform.runLater(() -> {
                            loadAdminView();
                        });
                        return;
                    }

                    // Standard User Checks
                    try {
                        com.google.gson.JsonObject metadata = service.getUserMetadata();

                        // 1. Ownership Check (Simple Boolean)
                        // If field is MISSING, we default to TRUE (Allowed) to avoid blocking legacy
                        // users
                        // unless explicitly set to FALSE. OR we can default to FALSE if strict.
                        // User requested: "ownership_payment: false" -> Block.
                        boolean ownershipPaid = true; // Default Allow
                        if (metadata.has("ownership_payment")) {
                            ownershipPaid = metadata.get("ownership_payment").getAsBoolean();
                        }
                        // --- CHECK EXPIRE DATES ---
                        boolean dataChanged = false;
                        java.util.Map<String, Object> expiryUpdates = new java.util.HashMap<>();
                        long nowMs = System.currentTimeMillis();

                        if (metadata.has("ownership_expiry")) {
                            try {
                                long expiry = metadata.get("ownership_expiry").getAsLong();
                                if (expiry > 0 && nowMs > expiry) {
                                    System.out.println("Ownership expired!");
                                    ownershipPaid = false;
                                    expiryUpdates.put("ownership_payment", false);
                                    expiryUpdates.put("ownership_expiry", 0);
                                    dataChanged = true;
                                }
                            } catch (Exception ignore) {
                            }
                        }

                        if (metadata.has("backup_expiry")) {
                            try {
                                long expiry = metadata.get("backup_expiry").getAsLong();
                                if (expiry > 0 && nowMs > expiry) {
                                    System.out.println("Backup expired!");
                                    expiryUpdates.put("monthly_cloud_backup", false);
                                    expiryUpdates.put("backup_expiry", 0);
                                    dataChanged = true;
                                }
                            } catch (Exception ignore) {
                            }
                        }

                        // Apply expiry updates immediately
                        if (dataChanged) {
                            service.updateUserFields(expiryUpdates);
                            // Refresh metadata? Or just rely on local vars?
                            // Local vars below need to reflect it.
                            // ownershipPaid is already updated above.
                            // We need to re-fetch or just flow through. check backupEnabled below.
                        }
                        // 1.5. Check Trial Period (30 Days)
                        // If not paid, check if within 30 days of creation
                        boolean isTrialActive = false;
                        if (!ownershipPaid) {
                            if (metadata.has("created_at")) {
                                String createdAtStr = metadata.get("created_at").getAsString();
                                try {
                                    // Supabase format: 2026-02-01T20:23:49.519334+00:00
                                    // Use OffsetDateTime or similar
                                    java.time.OffsetDateTime createdAt = java.time.OffsetDateTime.parse(createdAtStr);
                                    java.time.OffsetDateTime now = java.time.OffsetDateTime.now();
                                    long daysDiff = java.time.temporal.ChronoUnit.DAYS.between(createdAt, now);

                                    if (daysDiff < 30) {
                                        isTrialActive = true;
                                    } else {
                                        System.out.println("Trial expired. Days since creation: " + daysDiff);
                                    }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                    // If parse fails, fail safe (block) or unsafe (allow)?
                                    // Let's block to prevent abuse if format changes, but log it.
                                }
                            } else {
                                // No created_at (legacy?), assume expired if not paid.
                            }
                        }

                        // 2. Backup Check
                        boolean backupEnabled = true; // Default Allow
                        if (metadata.has("monthly_cloud_backup")) {
                            backupEnabled = metadata.get("monthly_cloud_backup").getAsBoolean();
                        }

                        // --- UPDATE EMAIL FOR ADMIN VIEW ---
                        // Only update if missing or different to save writes
                        if (!metadata.has("email") || !metadata.get("email").getAsString().equals(email)) {
                            java.util.Map<String, Object> updates = new java.util.HashMap<>();
                            updates.put("email", email);
                            service.updateUserFields(updates);
                        }

                        final boolean finalOwnershipPaid = ownershipPaid;
                        final boolean finalIsTrialActive = isTrialActive;
                        final boolean finalBackupEnabled = backupEnabled;

                        Platform.runLater(() -> {
                            if (!finalOwnershipPaid && !finalIsTrialActive) {
                                setLoading(false);
                                statusLabel.setText("Access Denied: Trial Expired.");
                                showOwnershipAlert();
                                return; // BLOCK LOGIN
                            }

                            // Update DataManager
                            com.meto.inventory.DataManager.getInstance().setBackupEnabled(finalBackupEnabled);

                            if (!finalBackupEnabled) {
                                showBackupDisabledAlert();
                            }

                            statusLabel.setText("Login successful! Syncing data...");
                            statusLabel.setStyle("-fx-text-fill: green;");

                            startSyncProcess();
                        });

                    } catch (Exception e) {
                        e.printStackTrace();
                        // Proceed on metadata error (e.g. network)
                        Platform.runLater(() -> {
                            statusLabel.setText("Login successful! (Check failed)");
                            startSyncProcess();
                        });
                    }

                } else {
                    Platform.runLater(() -> {
                        setLoading(false);
                        statusLabel.setText("Login failed. Check credentials.");
                    });
                }
            } catch (Exception ex) {
                ex.printStackTrace();
                Platform.runLater(() -> {
                    setLoading(false);
                    String msg = ex.getMessage();
                    if (msg.contains("INVALID_LOGIN_CREDENTIALS")) {
                        statusLabel.setText("Invalid email or password.");
                    } else if (msg.contains("EMAIL_NOT_FOUND")) {
                        statusLabel.setText("Account not found. Create one?");
                    } else {
                        statusLabel.setText("Error: " + msg);
                    }
                });
            }
        }).start();
    }

    private void loadAdminView() {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/AdminDashboard.fxml"));
            Parent root = loader.load();
            Stage stage = (Stage) loginButton.getScene().getWindow();
            Scene scene = new Scene(root, 1000, 600);
            scene.getStylesheets()
                    .add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());
            stage.setTitle("Admin Dashboard - ManagementSYS");
            stage.setScene(scene);
            stage.centerOnScreen();
        } catch (IOException e) {
            e.printStackTrace();
            statusLabel.setText("Failed to load Admin Dashboard.");
            setLoading(false);
        }
    }

    private void startSyncProcess() {
        // Perform Sync/Restore
        new Thread(() -> {
            try {
                // 1. Close current DB connection to release lock
                // We must do this before switching filenames or checking logs
                com.meto.inventory.DataManager.getInstance().getDbHelper().close();

                // 2. SWITCH DATABASE TO USER SPECIFIC FILE
                // This must happen for ALL users, regardless of backup status.
                try {
                    String currentUid = SupabaseService.getInstance().getCurrentUserId();
                    if (currentUid == null || currentUid.isEmpty())
                        currentUid = "unknown_user";

                    String newDbName = "inventory_" + currentUid.replaceAll("[^a-zA-Z0-9]", "_") + ".db";
                    java.nio.file.Path newDbPath = java.nio.file.Path.of(newDbName);
                    java.nio.file.Path oldDbPath = java.nio.file.Path.of("inventory.db");

                    // MIGRATION LOGIC (Legacy -> New)
                    if (!java.nio.file.Files.exists(newDbPath) && java.nio.file.Files.exists(oldDbPath)) {
                        try {
                            long size = java.nio.file.Files.size(oldDbPath);
                            if (size > 24000) {
                                System.out.println(
                                        "Migrating legacy database (" + size + " bytes) to user-specific file...");
                                java.nio.file.Files.copy(oldDbPath, newDbPath);
                            } else {
                                System.out.println(
                                        "Skipping migration of empty/decoy inventory.db (" + size + " bytes).");
                            }
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }

                    // PERFORM THE SWITCH
                    System.out.println("Switching database to: " + newDbName);
                    com.meto.inventory.DataManager.getInstance().resetDatabase(currentUid); // This sets the name
                } catch (Exception e) {
                    e.printStackTrace();
                    System.out.println("Critical Error switching database. Falling back to default.");
                }

                // 3. CHECK SUBSCRIPTION (Now that we are on the correct DB)
                if (!com.meto.inventory.DataManager.getInstance().isBackupEnabled()) {
                    System.out.println("Backup disabled logic triggered. Skipping cloud sync.");
                    Platform.runLater(() -> statusLabel.setText("Cloud Backup Disabled. Using Local Data."));

                    // Re-initialize DB connection immediately since we closed it (and resetDatabase
                    // might have touched it)
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                    Platform.runLater(() -> {
                        setLoading(false);
                        loadMainView();
                    });
                    return;
                }

                // 4. SYNC (If permitted)
                // Attempt Sync (Smart Restore)
                // CRITICAL FIX: Close the DB connection BEFORE syncing!
                // Attempting to overwrite a file while SQLite has it open causes
                // locks/corruption.

                // DATA CHECK: Must check if local data exists BEFORE closing connection
                java.io.File dbFile = new java.io.File(com.meto.inventory.DataManager.getInstance().getCurrentDbName());
                boolean localHasData = com.meto.inventory.DataManager.getInstance().getDbHelper().hasData();
                System.out.println("DEBUG SYNC: Target DB = " + dbFile.getName());
                System.out.println("DEBUG SYNC: DB Size = " + dbFile.length() + " bytes");
                System.out.println("DEBUG SYNC: hasData() = " + localHasData);

                // CRITICAL FIX: Close the DB connection BEFORE syncing!
                com.meto.inventory.DataManager.getInstance().getDbHelper().close();

                boolean restored = SupabaseService.getInstance().syncOnLogin(
                        com.meto.inventory.DataManager.getInstance().getCurrentDbName(), localHasData);

                // CRITICAL FIX: Re-open the DB connection AFTER sync is done.
                com.meto.inventory.DataManager.getInstance().getDbHelper().connect();

                if (restored) {
                    System.out.println("Database restored from cloud.");
                    Platform.runLater(() -> statusLabel.setText("Restored from Backup!"));
                } else {
                    System.out.println("Using local database (Newer or Offline).");
                }

                // 4. Re-initialize DB connection
                com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                // 5. Load UI
                Platform.runLater(() -> {
                    setLoading(false);
                    loadMainView();
                });

            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> {
                    setLoading(false);
                    statusLabel.setText("Sync Error: " + e.getMessage());
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();
                    loadMainView();
                });
            }
        }).start();
    }

    private void showOwnershipAlert() {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle("Account Expired");
        alert.setHeaderText("Ownership Payment Required");
        alert.setContentText(
                "Your trial has ended. Please purchase the app to continue using it.\n\nGo to meto.com/pay");

        javafx.scene.control.ButtonType payButton = new javafx.scene.control.ButtonType("Pay Now");
        alert.getButtonTypes().add(payButton);

        alert.showAndWait().ifPresent(response -> {
            if (response == payButton) {
                openPaymentLink();
            }
        });
    }

    private void showBackupDisabledAlert() {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(
                javafx.scene.control.Alert.AlertType.INFORMATION);
        alert.setTitle("Backup Disabled");
        alert.setHeaderText("Monthly Backup Disabled");
        alert.setContentText(
                "Cloud backup is currently turned off. Your data is safe locally.\nTo enable it, please contact support or subscribe at meto.com/subscribe");

        javafx.scene.control.ButtonType payButton = new javafx.scene.control.ButtonType("Subscribe");
        alert.getButtonTypes().add(payButton);

        alert.showAndWait().ifPresent(response -> {
            if (response == payButton) {
                openPaymentLink();
            }
        });
    }

    private void showBackupExpiredAlert() {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle("Backup Expired");
        alert.setHeaderText("Monthly Subscription Ended");
        alert.setContentText(
                "Your 30-day cloud backup period has ended. Syncing is now disabled.\n\nTo renew, please visit meto.com/subscribe");

        javafx.scene.control.ButtonType payButton = new javafx.scene.control.ButtonType("Renew Now");
        alert.getButtonTypes().add(payButton);

        alert.showAndWait().ifPresent(response -> {
            if (response == payButton) {
                openPaymentLink();
            }
        });
    }

    private void openPaymentLink() {
        try {
            java.awt.Desktop.getDesktop().browse(new java.net.URI("https://meto.com"));
        } catch (Exception e) {
            e.printStackTrace();
            // Fallback for Linux sometimes
            try {
                Runtime.getRuntime().exec("xdg-open https://meto.com");
            } catch (Exception ex) {
                statusLabel.setText("Could not open link: https://meto.com");
            }
        }
    }

    private void setLoading(boolean loading) {
        loginButton.setDisable(loading);
        emailField.setDisable(loading);
        passwordField.setDisable(loading);
        if (loading) {
            statusLabel.setText("Processing...");
            statusLabel.setStyle("-fx-text-fill: blue;");
        }
    }

    private void loadMainView() {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Main.fxml"));
            Parent root = loader.load();
            Stage stage = (Stage) loginButton.getScene().getWindow();

            Scene scene = new Scene(root, 1200, 720);
            scene.getStylesheets()
                    .add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());

            stage.setScene(scene);
            stage.centerOnScreen();
        } catch (IOException e) {
            e.printStackTrace();
            statusLabel.setText("Failed to load application.");
        }
    }
}
