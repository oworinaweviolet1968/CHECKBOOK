package com.meto.inventory.controllers;

import com.meto.inventory.services.FirebaseService;
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
                boolean success = FirebaseService.getInstance().signIn(email, password);
                Platform.runLater(() -> {
                    if (success) {
                        statusLabel.setText("Login successful! Syncing data...");
                        statusLabel.setStyle("-fx-text-fill: green;");

                        // Perform Sync/Restore
                        new Thread(() -> {
                            try {
                                // 1. Close current DB connection to release lock
                                com.meto.inventory.DataManager.getInstance().getDbHelper().close();

                                // 1.5. Check User Session (Prevent data bleed)
                                try {
                                    String sessionPath = "user_session.txt";
                                    String currentUid = FirebaseService.getInstance().getCurrentUserId();
                                    java.nio.file.Path sessionFile = java.nio.file.Path.of(sessionPath);

                                    if (java.nio.file.Files.exists(sessionFile)) {
                                        String lastUid = java.nio.file.Files.readString(sessionFile).trim();
                                        if (!lastUid.equals(currentUid)) {
                                            System.out.println("Different user detected. Clearing local database.");
                                            java.nio.file.Files.deleteIfExists(java.nio.file.Path.of("inventory.db"));
                                        }
                                    }
                                    // Save current user as last user
                                    java.nio.file.Files.writeString(sessionFile, currentUid);
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }

                                // 2. Attempt Sync (Smart Restore)
                                boolean restored = FirebaseService.getInstance().syncOnLogin("inventory.db");

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
                                    setLoading(false); // Enable controls just in case, though we switch view
                                    loadMainView();
                                });

                            } catch (Exception e) {
                                e.printStackTrace();
                                Platform.runLater(() -> {
                                    setLoading(false);
                                    statusLabel.setText("Sync Error: " + e.getMessage());
                                    // Proceed anyway after a delay or user action?
                                    // For now, let's try to load main view even if sync fails, but maybe strictly
                                    // warn?
                                    // Actually, if sync fails, we might still want to let them in, but DataManager
                                    // might be broken if Init failed.
                                    // Let's re-init safely.
                                    com.meto.inventory.DataManager.getInstance().getDbHelper().initializeDatabase();
                                    loadMainView();
                                });
                            }
                        }).start();

                    } else {
                        setLoading(false);
                        statusLabel.setText("Login failed. Check credentials.");
                    }
                });
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
