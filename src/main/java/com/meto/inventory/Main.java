package com.meto.inventory;

import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;

import javafx.scene.image.Image;
import atlantafx.base.theme.PrimerLight;

public class Main extends Application {
    @Override
    public void start(Stage primaryStage) throws Exception {
        Application.setUserAgentStylesheet(new PrimerLight().getUserAgentStylesheet());

        // Check for free OTA updates via Supabase
        com.meto.inventory.services.AutoUpdater.checkForUpdatesAsync();

        // Verify stored persistent device token on startup
        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
        boolean hasValidToken = service.verifyStoredTokenOnStartup();

        if (hasValidToken) {
            String currentUid = service.getCurrentUserId();
            com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(currentUid);
            loadMainView(primaryStage);
            triggerSync();
        } else {
            showLoginView(primaryStage);
        }
    }

    private void showLoginView(Stage stage) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Login.fxml"));
            Parent root = loader.load();
            Scene scene = new Scene(root, 1200, 720);
            scene.getStylesheets()
                    .add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());

            stage.setTitle("CHECKBOOK IMS");
            stage.getIcons()
                    .add(new Image(getClass().getResourceAsStream("/com/meto/inventory/views/images/logo.png")));
            stage.setScene(scene);
            stage.show();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void loadMainView(Stage stage) throws Exception {
        FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Main.fxml"));
        Parent root = loader.load();
        Scene scene = new Scene(root, 1200, 720);
        scene.getStylesheets()
                .add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());

        stage.setTitle("CHECKBOOK IMS");
        stage.getIcons()
                .add(new Image(getClass().getResourceAsStream("/com/meto/inventory/views/images/logo.png")));
        stage.setScene(scene);
        stage.show();
    }

    private void triggerSync() {
        // This mirrors the startSyncProcess in LoginController but for auto-login
        Thread syncThread = new Thread(() -> {
            try {
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService
                        .getInstance();
                String currentUid = service.getCurrentUserId();
                if (currentUid != null) {
                    com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(currentUid);

                    // We wrap all cloud operations in a try-catch so we gracefully fall back to local database if internet/auth fails
                    try {
                        com.meto.inventory.powersync.TokenManager tokenMgr = com.meto.inventory.powersync.TokenManager.getInstance();
                        tokenMgr.ensureTokenFresh();

                        tokenMgr.withValidToken(() -> {
                            // Fetch metadata
                            com.google.gson.JsonObject metadata = service.getUserMetadata();
                            
                            // Backup check
                            boolean backupEnabled = true;
                            if (metadata != null && metadata.has("monthly_cloud_backup")) {
                                backupEnabled = metadata.get("monthly_cloud_backup").getAsBoolean();
                            }

                            // Check backup expiry
                            long nowMs = System.currentTimeMillis();
                            boolean dataChanged = false;
                            java.util.Map<String, Object> expiryUpdates = new java.util.HashMap<>();

                            if (metadata != null && metadata.has("backup_expiry")) {
                                try {
                                    long expiry = metadata.get("backup_expiry").getAsLong();
                                    if (expiry > 0 && nowMs > expiry) {
                                        backupEnabled = false;
                                        expiryUpdates.put("monthly_cloud_backup", false);
                                        expiryUpdates.put("backup_expiry", 0);
                                        dataChanged = true;
                                    }
                                } catch (Exception ignore) {
                                }
                            }

                            if (dataChanged) {
                                service.updateUserFields(expiryUpdates);
                            }

                            com.meto.inventory.DataManager.getInstance().setBackupEnabled(backupEnabled);

                            if (!backupEnabled) {
                                String email = (metadata != null && metadata.has("email")) ? metadata.get("email").getAsString() : "your email";
                                System.out.println("Backup disabled logic triggered. Skipping cloud sync.");
                                
                                javafx.application.Platform.runLater(() -> {
                                    showBackupDisabledAlert(email);
                                });

                                com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();
                                com.meto.inventory.DataManager.getInstance().notifyDataChanged();
                                return null;
                            }

                            // Standard Sync
                            boolean localHasData = com.meto.inventory.DataManager.getInstance().getDbHelper().hasData();

                            service.syncOnLogin(com.meto.inventory.DataManager.getInstance().getCurrentDbName(), localHasData, false);
                            return null;
                        });

                    } catch (Exception cloudEx) {
                        System.err.println("Cloud sync failed during auto-login, falling back to local-only DB: " + cloudEx.getMessage());
                        service.notifyStatus("Offline (Local Database)");
                    }

                    com.meto.inventory.DataManager.getInstance().getDbHelper().connect();
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                    // Start 30-second heartbeat monitor
                    com.meto.inventory.powersync.HeartbeatMonitor.getInstance().start();

                    // Notify UI after everything is ready (Trigger cloud sync push for unsynced local data)
                    com.meto.inventory.DataManager.getInstance().notifyDataChanged(true);
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        });
        syncThread.setDaemon(true);
        syncThread.start();
    }

    private void triggerOfflineMode(String currentUid) {
        Thread offlineThread = new Thread(() -> {
            try {
                System.out.println("Initializing Offline Database for: " + currentUid);
                com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(currentUid);
                com.meto.inventory.DataManager.getInstance().getDbHelper().connect();
                com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();
                com.meto.inventory.DataManager.getInstance().notifyDataChanged(false);
                
                // Let the UI know we are running in Offline Mode
                com.meto.inventory.services.SupabaseService.getInstance().notifyStatus("Offline (Local Database)");
            } catch (Exception e) {
                e.printStackTrace();
            }
        });
        offlineThread.setDaemon(true);
        offlineThread.start();
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

    @Override
    public void stop() throws Exception {
        super.stop();
        try {
            com.meto.inventory.powersync.PowerSyncEngine.getInstance().stop();
            com.meto.inventory.powersync.HeartbeatMonitor.getInstance().stop();
        } catch (Exception ignore) {
        }
        System.exit(0);
    }

    public static void main(String[] args) {
        launch(args);
    }
}
