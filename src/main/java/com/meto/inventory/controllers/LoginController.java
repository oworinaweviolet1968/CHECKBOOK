package com.meto.inventory.controllers;

import com.meto.inventory.services.SupabaseService;
import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBar;
import javafx.scene.control.ButtonType;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.ProgressIndicator;
import javafx.scene.control.TextField;
import javafx.stage.Stage;

import java.io.IOException;

public class LoginController {

    @FXML
    private TextField checkbookIdField;
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

        // Auto-formatting listener for Checkbook ID input (uppercase & prefix formatting)
        checkbookIdField.textProperty().addListener((obs, oldText, newText) -> {
            if (newText == null || newText.isEmpty()) return;
            // If user enters email address, keep full text as is
            if (newText.contains("@")) return;

            String cleaned = newText.toUpperCase().replaceAll("[^A-Z0-9-]", "");
            if (!cleaned.startsWith("CK-") && cleaned.length() > 0) {
                if (cleaned.startsWith("CK")) {
                    cleaned = "CK-" + cleaned.substring(Math.min(2, cleaned.length()));
                } else {
                    cleaned = "CK-" + cleaned;
                }
            }
            if (cleaned.length() > 9 && !cleaned.contains("@")) {
                cleaned = cleaned.substring(0, 9);
            }
            if (!cleaned.equals(newText)) {
                final String formatted = cleaned;
                Platform.runLater(() -> {
                    checkbookIdField.setText(formatted);
                    checkbookIdField.positionCaret(formatted.length());
                });
            }
        });

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
        String inputId = checkbookIdField.getText().trim();

        if (inputId.isEmpty()) {
            statusLabel.setText("Please enter your Checkbook ID.");
            return;
        }

        setLoading(true);

        new Thread(() -> {
            try {
                SupabaseService service = SupabaseService.getInstance();
                String formattedCheckbookId = inputId.toUpperCase();
                if (!formattedCheckbookId.contains("@") && !formattedCheckbookId.startsWith("CK-")) {
                    formattedCheckbookId = "CK-" + formattedCheckbookId;
                }

                // Initiate pairing request
                com.google.gson.JsonObject initRes = service.initiatePairingRequest(formattedCheckbookId);
                if (initRes == null || !initRes.has("success") || !initRes.get("success").getAsBoolean()) {
                    String errMsg = (initRes != null && initRes.has("message")) ? initRes.get("message").getAsString() : "Checkbook ID not found. Find your ID inside your Mobile App under Settings > Checkbook ID.";
                    Platform.runLater(() -> {
                        setLoading(false);
                        statusLabel.setText(errMsg);
                        statusLabel.setStyle("-fx-text-fill: red;");
                    });
                    return;
                }

                String sessionId = initRes.get("session_id").getAsString();
                String targetEmail = initRes.has("email") ? initRes.get("email").getAsString() : "";
                String targetUserId = initRes.has("user_id") ? initRes.get("user_id").getAsString() : "";

                Platform.runLater(() -> {
                    statusLabel.setText("Approval request sent to your mobile device. Please tap Accept to authorize this desktop.");
                    statusLabel.setStyle("-fx-text-fill: #0284C7;");
                });

                // Poll status every 3 seconds for up to 120 seconds
                boolean approved = false;
                String token = null;

                for (int secondsLeft = 120; secondsLeft > 0; secondsLeft -= 3) {
                    Thread.sleep(3000);
                    com.google.gson.JsonObject statusRes = service.checkPairingStatus(sessionId);

                    if (statusRes != null && statusRes.has("status")) {
                        String st = statusRes.get("status").getAsString();
                        if ("APPROVED".equalsIgnoreCase(st)) {
                            approved = true;
                            if (statusRes.has("pairing_token") && !statusRes.get("pairing_token").isJsonNull()) {
                                token = statusRes.get("pairing_token").getAsString();
                            }
                            if (statusRes.has("email") && !statusRes.get("email").isJsonNull()) {
                                targetEmail = statusRes.get("email").getAsString();
                            }
                            if (statusRes.has("user_id") && !statusRes.get("user_id").isJsonNull()) {
                                targetUserId = statusRes.get("user_id").getAsString();
                            }
                            break;
                        } else if ("REJECTED".equalsIgnoreCase(st)) {
                            Platform.runLater(() -> {
                                setLoading(false);
                                statusLabel.setText("Login request was declined on your mobile device.");
                                statusLabel.setStyle("-fx-text-fill: red;");
                            });
                            return;
                        } else if ("EXPIRED".equalsIgnoreCase(st)) {
                            break;
                        }
                    }

                    final int remaining = secondsLeft - 3;
                    Platform.runLater(() -> {
                        statusLabel.setText("Waiting for mobile approval (" + Math.max(0, remaining) + "s remaining)... Please tap Accept on your mobile app.");
                        statusLabel.setStyle("-fx-text-fill: #0284C7;");
                    });
                }

                if (!approved) {
                    Platform.runLater(() -> {
                        setLoading(false);
                        statusLabel.setText("Connection request timed out. Please tap Login to try again.");
                        statusLabel.setStyle("-fx-text-fill: red;");
                    });
                    return;
                }

                // Approved pairing! Perform strict user license/ownership checks BEFORE saving session to disk
                final String finalEmail = targetEmail;
                final String finalUserId = targetUserId;
                final String finalToken = token;

                try {
                    com.google.gson.JsonObject metadata = service.getUserMetadata(finalUserId, finalEmail);
                    boolean ownershipPaid = service.isOwnershipOrTrialValid(metadata);
                    boolean backupEnabled = (metadata != null && metadata.has("monthly_cloud_backup")) ? metadata.get("monthly_cloud_backup").getAsBoolean() : true;

                    final boolean finalOwnershipPaid = ownershipPaid;
                    final boolean finalBackupEnabled = backupEnabled;

                    Platform.runLater(() -> {
                        if (!finalOwnershipPaid) {
                            // Purge any local session file/tokens
                            service.clearSession();
                            setLoading(false);
                            statusLabel.setText("Access Denied: 7-Day Free Trial Expired. License Required.");
                            statusLabel.setStyle("-fx-text-fill: red;");
                            showOwnershipAlert(finalEmail);
                            return;
                        }

                        // Atomic Persistence: Save pairing token to disk ONLY on full verification success
                        service.savePairingToken(finalToken, finalUserId, finalEmail);

                        com.meto.inventory.DataManager.getInstance().setBackupEnabled(finalBackupEnabled);

                        if (!finalBackupEnabled) {
                            showBackupDisabledAlert(finalEmail);
                        }

                        // Load App
                        com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(service.getCurrentUserId());
                        loadMainView();
                    });

                } catch (Exception ex) {
                    service.clearSession();
                    Platform.runLater(() -> {
                        setLoading(false);
                        statusLabel.setText("Error verifying account license. Please try again.");
                        statusLabel.setStyle("-fx-text-fill: red;");
                    });
                }

            } catch (Exception e) {
                Platform.runLater(() -> {
                    setLoading(false);
                    statusLabel.setText("Error: " + e.getMessage());
                    statusLabel.setStyle("-fx-text-fill: red;");
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

                    // PERFORM THE SWITCH
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
                        com.meto.inventory.DataManager.getInstance().getCurrentDbName(), localHasData, false);

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

    private static long parseTimestamp(String tsStr) {
        if (tsStr == null || tsStr.trim().isEmpty()) return 0;
        try {
            return Long.parseLong(tsStr.trim());
        } catch (NumberFormatException e) {
            try {
                String clean = tsStr.replace("Z", "").replace(" ", "T");
                if (clean.contains(".")) {
                    clean = clean.substring(0, clean.indexOf("."));
                }
                java.time.LocalDateTime ldt = java.time.LocalDateTime.parse(clean);
                return ldt.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
            } catch (Exception ex) {
                return 0;
            }
        }
    }

    private static boolean isTrialActive(com.google.gson.JsonObject metadata) {
        if (metadata == null) return true;
        long now = System.currentTimeMillis();

        if (metadata.has("account_status")) {
            String status = metadata.get("account_status").getAsString();
            if ("trial_active".equalsIgnoreCase(status) || "active".equalsIgnoreCase(status)) return true;
        }
        if (metadata.has("subscription_status")) {
            String status = metadata.get("subscription_status").getAsString();
            if ("TRIAL_ACTIVE".equalsIgnoreCase(status) || "ACTIVE".equalsIgnoreCase(status)) return true;
        }

        if (metadata.has("trial_expires_at") && !metadata.get("trial_expires_at").isJsonNull()) {
            try {
                String expStr = metadata.get("trial_expires_at").getAsString();
                long expMs = parseTimestamp(expStr);
                if (expMs > now) {
                    return true;
                }
            } catch (Exception ignore) {}
        }

        String createdStr = null;
        if (metadata.has("trial_started_at") && !metadata.get("trial_started_at").isJsonNull()) {
            createdStr = metadata.get("trial_started_at").getAsString();
        } else if (metadata.has("created_at") && !metadata.get("created_at").isJsonNull()) {
            createdStr = metadata.get("created_at").getAsString();
        }

        if (createdStr != null) {
            long createdMs = parseTimestamp(createdStr);
            if (createdMs > 0 && (now - createdMs) < (7L * 24 * 3600 * 1000)) {
                return true;
            }
        }

        // If trial timestamp metadata field is not present or newly created account, default to active trial (7 days)
        if (createdStr == null && (!metadata.has("ownership_payment") || metadata.get("ownership_payment").getAsBoolean())) {
            return true;
        }

        return false;
    }

    private static boolean isOwnershipOrTrialValid(com.google.gson.JsonObject metadata) {
        if (metadata == null) return true;

        if (isTrialActive(metadata)) {
            return true;
        }

        boolean ownershipPaid = true;
        if (metadata.has("ownership_payment")) {
            ownershipPaid = metadata.get("ownership_payment").getAsBoolean();
        }

        if (metadata.has("ownership_expiry")) {
            try {
                long expiry = metadata.get("ownership_expiry").getAsLong();
                if (expiry > 0 && System.currentTimeMillis() > expiry) {
                    ownershipPaid = false;
                }
            } catch (Exception ignore) {}
        }

        return ownershipPaid;
    }

    private void showOwnershipAlert(String email) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(javafx.scene.control.Alert.AlertType.WARNING);
        alert.setTitle("Free Trial Expired");
        alert.setHeaderText("Ownership License Required");

        javafx.scene.text.TextFlow textFlow = new javafx.scene.text.TextFlow();
        javafx.scene.text.Text t1 = new javafx.scene.text.Text(
                "Your 7-Day Free Trial has ended. Please subscribe or activate your license to continue using CheckBook.\n\n");
        javafx.scene.text.Text t2 = new javafx.scene.text.Text("Customer Support Helpline:\n");
        t2.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t3 = new javafx.scene.text.Text("076 031 5703\n\n");
        t3.setStyle("-fx-font-weight: bold; -fx-font-size: 16px;");
        javafx.scene.text.Text t4 = new javafx.scene.text.Text("Account Email: ");
        javafx.scene.text.Text t5 = new javafx.scene.text.Text(email + "\n\n");
        t5.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t6 = new javafx.scene.text.Text(
                "Contact our customer support helpline for assistance with account activation or inquiries.");

        textFlow.getChildren().addAll(t1, t2, t3, t4, t5, t6);
        alert.getDialogPane().setContent(textFlow);

        javafx.scene.control.ButtonType closeBtn = new javafx.scene.control.ButtonType("Close",
                javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        alert.getButtonTypes().setAll(closeBtn);
        alert.showAndWait();
    }

    private void showBackupDisabledAlert(String email) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(
                javafx.scene.control.Alert.AlertType.INFORMATION);
        alert.setTitle("Backup Status");
        alert.setHeaderText("Monthly Backup Disabled");

        javafx.scene.text.TextFlow textFlow = new javafx.scene.text.TextFlow();
        javafx.scene.text.Text t1 = new javafx.scene.text.Text(
                "Cloud backup is currently inactive. Your data remains stored safely on your local computer.\n\n");
        javafx.scene.text.Text t2 = new javafx.scene.text.Text("Customer Support Helpline:\n");
        t2.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t3 = new javafx.scene.text.Text("076 031 5703\n\n");
        t3.setStyle("-fx-font-weight: bold; -fx-font-size: 16px;");
        javafx.scene.text.Text t4 = new javafx.scene.text.Text("Account Email: ");
        javafx.scene.text.Text t5 = new javafx.scene.text.Text(email + "\n\n");
        t5.setStyle("-fx-font-weight: bold;");
        javafx.scene.text.Text t6 = new javafx.scene.text.Text(
                "Contact our customer support helpline for assistance with cloud backup activation or inquiries.");

        textFlow.getChildren().addAll(t1, t2, t3, t4, t5, t6);
        alert.getDialogPane().setContent(textFlow);

        javafx.scene.control.ButtonType closeBtn = new javafx.scene.control.ButtonType("Close",
                javafx.scene.control.ButtonBar.ButtonData.OK_DONE);
        alert.getButtonTypes().setAll(closeBtn);
        alert.showAndWait();
    }

    private void setLoading(boolean loading) {
        loginButton.setDisable(loading);
        checkbookIdField.setDisable(loading);
        if (passwordField != null) {
            passwordField.setDisable(loading);
        }
        if (loading) {
            statusLabel.setText("Processing...");
            statusLabel.setStyle("-fx-text-fill: blue;");
            ProgressIndicator spinner = new ProgressIndicator();
            spinner.setPrefSize(18, 18);
            spinner.setMaxSize(18, 18);
            loginButton.setGraphic(spinner);
        } else {
            loginButton.setGraphic(null);
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
        String email = checkbookIdField.getText().trim();
        Stage ownerStage = (Stage) mobileLoginButton.getScene().getWindow();

        com.meto.inventory.components.MobileLoginModal modal = new com.meto.inventory.components.MobileLoginModal(
            ownerStage,
            email,
            new com.meto.inventory.components.MobileLoginModal.LoginCallback() {
                @Override
                public void onSuccess(String refreshToken, String userEmail) {
                    setLoading(true);
                    statusLabel.setText("Login approved! Syncing...");
                    statusLabel.setStyle("-fx-text-fill: green;");

                    new Thread(() -> {
                        try {
                            SupabaseService service = SupabaseService.getInstance();
                            boolean success;
                            if (refreshToken.contains(":::")) {
                                String[] parts = refreshToken.split(":::", 2);
                                String accToken = parts[0];
                                String refToken = parts.length > 1 ? parts[1] : "";
                                success = service.signInWithAccessToken(accToken, refToken);
                            } else {
                                success = service.signInWithRefreshToken(refreshToken);
                            }

                            if (success) {
                                Platform.runLater(() -> {
                                    startSyncProcess();
                                });
                            } else {
                                Platform.runLater(() -> {
                                    statusLabel.setText("Login failed after approval (invalid session token).");
                                    setLoading(false);
                                });
                            }
                        } catch (Exception ex) {
                            ex.printStackTrace();
                            Platform.runLater(() -> {
                                statusLabel.setText("Error signing in: " + ex.getMessage());
                                setLoading(false);
                            });
                        }
                    }).start();
                }

                @Override
                public void onError(String message) {
                    statusLabel.setText(message);
                    statusLabel.setStyle("-fx-text-fill: red;");
                }
            }
        );

        modal.show();
    }
}
