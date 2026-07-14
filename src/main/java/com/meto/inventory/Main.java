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

        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
        
        // Restore last active userId from saved JSON session first if present
        String savedToken = service.loadSession();

        if (savedToken != null) {
            // Show a splash or just attempt silent login
            new Thread(() -> {
                try {
                    boolean success = service.signInWithRefreshToken(savedToken);
                    if (success) {
                        javafx.application.Platform.runLater(() -> {
                            try {
                                loadMainView(primaryStage);
                                // Trigger sync in background
                                triggerSync();
                            } catch (Exception e) {
                                e.printStackTrace();
                                showLoginView(primaryStage);
                            }
                        });
                        return;
                    } else {
                        // Refresh token was invalid/expired (HTTP 400/401/etc.) -> Go to login screen
                        javafx.application.Platform.runLater(() -> showLoginView(primaryStage));
                    }
                } catch (Exception e) {
                    // Network connection failed (IOException/ConnectException/etc.) -> OFFLINE MODE
                    System.err.println("Offline mode active: Network error during auto-login: " + e.getMessage());
                    
                    String localUid = service.getCurrentUserId();
                    if (localUid != null) {
                        // User has an active local session! Let them in offline!
                        javafx.application.Platform.runLater(() -> {
                            try {
                                loadMainView(primaryStage);
                                // Trigger offline local DB setup
                                triggerOfflineMode(localUid);
                            } catch (Exception ex) {
                                ex.printStackTrace();
                                showLoginView(primaryStage);
                            }
                        });
                    } else {
                        // No cached UID, must authenticate online
                        javafx.application.Platform.runLater(() -> showLoginView(primaryStage));
                    }
                }
            }).start();
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

            stage.setTitle("METO IMS");
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

        stage.setTitle("METO IMS");
        stage.getIcons()
                .add(new Image(getClass().getResourceAsStream("/com/meto/inventory/views/images/logo.png")));
        stage.setScene(scene);
        stage.show();
    }

    private void triggerSync() {
        // This mirrors the startSyncProcess in LoginController but for auto-login
        new Thread(() -> {
            try {
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService
                        .getInstance();
                String currentUid = service.getCurrentUserId();
                if (currentUid != null) {
                    com.meto.inventory.DataManager.getInstance().switchDatabaseOnly(currentUid);

                    // We wrap all cloud operations in a try-catch so we gracefully fall back to local database if internet goes down midway
                    try {
                        // Fetch metadata
                        com.google.gson.JsonObject metadata = service.getUserMetadata();
                        
                        // Backup check
                        boolean backupEnabled = true;
                        if (metadata.has("monthly_cloud_backup")) {
                            backupEnabled = metadata.get("monthly_cloud_backup").getAsBoolean();
                        }

                        // Check backup expiry
                        long nowMs = System.currentTimeMillis();
                        boolean dataChanged = false;
                        java.util.Map<String, Object> expiryUpdates = new java.util.HashMap<>();

                        if (metadata.has("backup_expiry")) {
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
                            String email = metadata.has("email") ? metadata.get("email").getAsString() : "your email";
                            System.out.println("Backup disabled logic triggered. Skipping cloud sync.");
                            
                            javafx.application.Platform.runLater(() -> {
                                showBackupDisabledAlert(email);
                            });

                            com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();
                            com.meto.inventory.DataManager.getInstance().notifyDataChanged();
                            return;
                        }

                        // Standard Sync
                        boolean localHasData = com.meto.inventory.DataManager.getInstance().getDbHelper().hasData();

                        service.syncOnLogin(com.meto.inventory.DataManager.getInstance().getCurrentDbName(), localHasData, false);

                    } catch (Exception cloudEx) {
                        System.err.println("Cloud sync failed during auto-login, falling back to local-only DB: " + cloudEx.getMessage());
                        service.notifyStatus("Offline (Local Database)");
                    }

                    com.meto.inventory.DataManager.getInstance().getDbHelper().connect();
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                    // Notify UI after everything is ready (Trigger cloud sync push for unsynced local data)
                    com.meto.inventory.DataManager.getInstance().notifyDataChanged(true);
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }

    private void triggerOfflineMode(String currentUid) {
        new Thread(() -> {
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
        }).start();
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

    public static void main(String[] args) {
        launch(args);
    }
}
