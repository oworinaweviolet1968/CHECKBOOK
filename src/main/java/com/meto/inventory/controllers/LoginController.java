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
    private Button mobileLoginButton;
    @FXML
    private Label statusLabel;

    @FXML
    private javafx.scene.control.ProgressBar syncProgressBar;

    @FXML
    public void initialize() {
        loginButton.setOnAction(e -> handleLogin());
        mobileLoginButton.setOnAction(e -> handleMobileLogin());

        // Listen for progress updates
        SupabaseService.getInstance().addProgressListener(progress -> {
            Platform.runLater(() -> {
                if (progress <= 0 || progress >= 1.0) {
                    syncProgressBar.setVisible(false);
                    syncProgressBar.setManaged(false);
                } else {
                    syncProgressBar.setVisible(true);
                    syncProgressBar.setManaged(true);
                    syncProgressBar.setProgress(progress);
                }
            });
        });
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
                        final boolean finalBackupEnabled = backupEnabled;

                        Platform.runLater(() -> {
                            if (!finalOwnershipPaid) {
                                setLoading(false);
                                statusLabel.setText("Access Denied: Payment Required.");
                                showOwnershipAlert(email);
                                return; // BLOCK LOGIN
                            }

                            // Update DataManager
                            com.meto.inventory.DataManager.getInstance().setBackupEnabled(finalBackupEnabled);

                            if (!finalBackupEnabled) {
                                showBackupDisabledAlert(email);
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

                    String appDir = com.meto.inventory.DatabaseHelper.getAppDir();
                    java.nio.file.Path newDbPath = java.nio.file.Path.of(appDir, newDbName);
                    java.nio.file.Path oldDbPath = java.nio.file.Path.of(appDir, "inventory.db");

                    // MIGRATION LOGIC (Legacy -> New)
                    if (!java.nio.file.Files.exists(newDbPath) && java.nio.file.Files.exists(oldDbPath)) {
                        try {
                            System.out.println("Migrating legacy database to user-specific file...");
                            java.nio.file.Files.copy(oldDbPath, newDbPath);
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }

                    // PERFORM THE SWITCH
                    System.out.println("Switching database to: " + newDbName);
                    com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(currentUid); // This sets the name
                } catch (Exception e) {
                    e.printStackTrace();
                    System.out.println("Critical Error switching database. Falling back to default.");
                }

                // 3. CHECK SUBSCRIPTION (Now that we are on the correct DB)
                if (!com.meto.inventory.DataManager.getInstance().isBackupEnabled()) {
                    System.out.println("Backup disabled logic triggered. Skipping cloud sync.");
                    Platform.runLater(() -> statusLabel.setText("Cloud Backup Disabled. Using Local Data."));

                    // Re-initialize DB connection immediately since we closed it (and
                    // switchDatabaseOnly
                    // might have touched it)
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                    // NOTIFY UI NOW since we are done with the DB logic
                    com.meto.inventory.DataManager.getInstance().notifyDataChanged();

                    Platform.runLater(() -> {
                        setLoading(false);
                        loadMainView();
                    });
                    return;
                }

                // 4. SYNC (If permitted)
                // Attempt Sync (Smart Restore)
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

                // 5. NOTIFY UI LATE: Now that the DB is open and data is synced
                com.meto.inventory.DataManager.getInstance().notifyDataChanged();

                // 6. Load UI
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
                    com.meto.inventory.DataManager.getInstance().notifyDataChanged();
                    loadMainView();
                });
            }
        }).start();
    }

    private void showOwnershipAlert(String email) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle("Account Expired");
        alert.setHeaderText("Ownership Payment Required");

        javafx.scene.text.TextFlow textFlow = new javafx.scene.text.TextFlow();
        javafx.scene.text.Text t1 = new javafx.scene.text.Text(
                "Access has been denied. Please complete your payment to activate CheckBook Pro.\n\n");
        javafx.scene.text.Text t2 = new javafx.scene.text.Text("Send 203,000 UGX to MTN Number:\n");
        javafx.scene.text.Text t3 = new javafx.scene.text.Text("076 031 5703\n");
        t3.setStyle("-fx-font-weight: bold; -fx-font-size: 16px;");
        javafx.scene.text.Text t4 = new javafx.scene.text.Text("Name: Oworinawe Prince Beckham\n\n");
        javafx.scene.text.Text t5 = new javafx.scene.text.Text(
                "After sending, please WhatsApp your receipt footprint and your account email ");
        javafx.scene.text.Text t6 = new javafx.scene.text.Text(email);
        t6.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t7 = new javafx.scene.text.Text(" to ");
        javafx.scene.text.Text t8 = new javafx.scene.text.Text("076 031 5703");
        t8.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t9 = new javafx.scene.text.Text(" for immediate ownership activation.");

        textFlow.getChildren().addAll(t1, t2, t3, t4, t5, t6, t7, t8, t9);
        alert.getDialogPane().setContent(textFlow);

        javafx.scene.control.ButtonType closeBtn = new javafx.scene.control.ButtonType("Close",
                javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        alert.getButtonTypes().setAll(closeBtn);
        alert.showAndWait();
    }

    private void showBackupDisabledAlert(String email) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(
                javafx.scene.control.Alert.AlertType.INFORMATION);
        alert.setTitle("Backup Disabled");
        alert.setHeaderText("Monthly Backup Disabled");

        javafx.scene.text.TextFlow textFlow = new javafx.scene.text.TextFlow();
        javafx.scene.text.Text t1 = new javafx.scene.text.Text(
                "Cloud backup is turned off. Your data is safe locally.\n\nTo activate your cloud subscription, send 15,000 UGX to MTN Number:\n");
        javafx.scene.text.Text t2 = new javafx.scene.text.Text("076 031 5703\n");
        t2.setStyle("-fx-font-weight: bold; -fx-font-size: 14px;");
        javafx.scene.text.Text t3 = new javafx.scene.text.Text("Name: Oworinawe Prince Beckham\n\n");
        javafx.scene.text.Text t4 = new javafx.scene.text.Text(
                "Then WhatsApp your receipt footprint and account email ");
        javafx.scene.text.Text t5 = new javafx.scene.text.Text(email);
        t5.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t6 = new javafx.scene.text.Text(" to ");
        javafx.scene.text.Text t7 = new javafx.scene.text.Text("076 031 5703");
        t7.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t8 = new javafx.scene.text.Text(" for immediate cloud activation.");

        textFlow.getChildren().addAll(t1, t2, t3, t4, t5, t6, t7, t8);
        alert.getDialogPane().setContent(textFlow);

        javafx.scene.control.ButtonType closeBtn = new javafx.scene.control.ButtonType("Close",
                javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        alert.getButtonTypes().setAll(closeBtn);
        alert.showAndWait();
    }

    private void showBackupExpiredAlert(String email) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle("Backup Expired");
        alert.setHeaderText("Monthly Subscription Ended");

        javafx.scene.text.TextFlow textFlow = new javafx.scene.text.TextFlow();
        textFlow.getChildren().addAll(
                new javafx.scene.text.Text(
                        "Your 30-day cloud backup period has ended. Syncing is now disabled.\n\nTo renew, please follow the payment instructions (15,000 UGX) to MTN number 076 031 5703."));
        alert.getDialogPane().setContent(textFlow);

        javafx.scene.control.ButtonType closeBtn = new javafx.scene.control.ButtonType("Close",
                javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        alert.getButtonTypes().setAll(closeBtn);
        alert.showAndWait();
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

    private void handleMobileLogin() {
        String email = emailField.getText().trim();
        if (email.isEmpty()) {
            statusLabel.setText("Please enter your email first.");
            return;
        }

        setLoading(true);
        statusLabel.setText("Check your mobile app for a login prompt...");
        statusLabel.setStyle("-fx-text-fill: #2196F3;");

        new Thread(() -> {
            String requestId = null;
            try {
                SupabaseService service = SupabaseService.getInstance();
                requestId = service.createLoginRequest(email);

                long startTime = System.currentTimeMillis();
                boolean approved = false;
                String refreshToken = null;

                while (System.currentTimeMillis() - startTime < 120000) {
                    com.google.gson.JsonObject request = service.pollLoginRequest(requestId);
                    if (request != null) {
                        String status = request.get("status").getAsString();
                        if ("approved".equals(status)) {
                            approved = true;
                            if (request.has("refresh_token") && !request.get("refresh_token").isJsonNull()) {
                                refreshToken = request.get("refresh_token").getAsString();
                            }
                            break;
                        } else if ("rejected".equals(status)) {
                            break;
                        }
                    }
                    Thread.sleep(3000);
                }

                if (approved && refreshToken != null) {
                    boolean success = service.signInWithRefreshToken(refreshToken);
                    if (success) {
                        Platform.runLater(() -> {
                            statusLabel.setText("Login approved! Syncing...");
                            statusLabel.setStyle("-fx-text-fill: green;");
                            startSyncProcess();
                        });
                    } else {
                        Platform.runLater(() -> {
                            statusLabel.setText("Login failed after approval.");
                            setLoading(false);
                        });
                    }
                } else {
                    Platform.runLater(() -> {
                        statusLabel.setText("Login request timed out or was rejected.");
                        setLoading(false);
                    });
                }

            } catch (Exception ex) {
                ex.printStackTrace();
                Platform.runLater(() -> {
                    statusLabel.setText("Mobile login error: " + ex.getMessage());
                    setLoading(false);
                });
            } finally {
                if (requestId != null) {
                    SupabaseService.getInstance().deleteLoginRequest(requestId);
                }
            }
        }).start();
    }
}
