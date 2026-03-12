package com.meto.inventory;

import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;

import javafx.scene.image.Image;

public class Main extends Application {
    @Override
    public void start(Stage primaryStage) throws Exception {
        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
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
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
                javafx.application.Platform.runLater(() -> showLoginView(primaryStage));
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

                    // Standard Sync
                    boolean localHasData = com.meto.inventory.DataManager.getInstance().getDbHelper().hasData();
                    com.meto.inventory.DataManager.getInstance().getDbHelper().close();

                    service.syncOnLogin(com.meto.inventory.DataManager.getInstance().getCurrentDbName(), localHasData);

                    com.meto.inventory.DataManager.getInstance().getDbHelper().connect();
                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();

                    // Notify UI after everything is ready
                    com.meto.inventory.DataManager.getInstance().notifyDataChanged();
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
