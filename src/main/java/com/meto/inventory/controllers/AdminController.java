package com.meto.inventory.controllers;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.meto.inventory.services.SupabaseService;
import javafx.application.Platform;
import javafx.beans.property.BooleanProperty;
import javafx.beans.property.SimpleBooleanProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.control.cell.CheckBoxTableCell;
import javafx.stage.Stage;

import java.util.HashMap;
import java.util.Map;

public class AdminController {

    @FXML
    private TableView<AdminUser> usersTable;
    @FXML
    private TableColumn<AdminUser, String> uidColumn;
    @FXML
    private TableColumn<AdminUser, String> emailColumn;
    @FXML
    private TableColumn<AdminUser, Boolean> ownershipColumn;
    @FXML
    private TableColumn<AdminUser, String> ownershipExpiryColumn;
    @FXML
    private TableColumn<AdminUser, Boolean> backupColumn;
    @FXML
    private TableColumn<AdminUser, String> backupExpiryColumn;
    @FXML
    private TableColumn<AdminUser, String> lastBackupColumn;
    @FXML
    private TableColumn<AdminUser, Void> resetPasswordColumn;
    @FXML
    private Button refreshButton;
    @FXML
    private Button logoutButton;
    @FXML
    private Button scanButton;
    @FXML
    private Label statusLabel;
    @FXML
    private TextField newUserEmail;
    @FXML
    private PasswordField newUserPass;
    @FXML
    private Button createUserButton;

    private final ObservableList<AdminUser> userList = FXCollections.observableArrayList();
    private final java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm");

    @FXML
    public void initialize() {
        setupTable();
        refreshButton.setOnAction(e -> loadUsers());
        logoutButton.setOnAction(e -> handleLogout());
        scanButton.setOnAction(e -> scanAndFix());
        createUserButton.setOnAction(e -> handleCreateUser());

        loadUsers();
    }

    private void handleCreateUser() {
        String email = newUserEmail.getText().trim();
        String password = newUserPass.getText();

        if (email.isEmpty() || password.isEmpty()) {
            statusLabel.setText("Enter email & password!");
            return;
        }

        statusLabel.setText("Creating user...");
        createUserButton.setDisable(true);

        new Thread(() -> {
            try {
                boolean success = SupabaseService.getInstance().adminCreateUser(email, password);
                Platform.runLater(() -> {
                    if (success) {
                        statusLabel.setText("User created: " + email);
                        newUserEmail.clear();
                        newUserPass.clear();
                        loadUsers(); // Refresh list
                    } else {
                        statusLabel.setText("Failed to create user. See logs.");
                    }
                    createUserButton.setDisable(false);
                });
            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> {
                    statusLabel.setText("Error: " + e.getMessage());
                    createUserButton.setDisable(false);
                });
            }
        }).start();
    }

    private void setupTable() {
        uidColumn.setCellValueFactory(cellData -> cellData.getValue().uidProperty());
        emailColumn.setCellValueFactory(cellData -> cellData.getValue().emailProperty());

        ownershipColumn.setCellValueFactory(cellData -> cellData.getValue().ownershipProperty());
        ownershipColumn.setCellFactory(CheckBoxTableCell.forTableColumn(ownershipColumn));
        ownershipColumn.setEditable(true);

        ownershipExpiryColumn.setCellValueFactory(cellData -> cellData.getValue().ownershipExpiryProperty());

        backupColumn.setCellValueFactory(cellData -> cellData.getValue().backupProperty());
        backupColumn.setCellFactory(CheckBoxTableCell.forTableColumn(backupColumn));
        backupColumn.setEditable(true);

        lastBackupColumn.setCellValueFactory(cellData -> cellData.getValue().lastBackupProperty());
        backupExpiryColumn.setCellValueFactory(cellData -> cellData.getValue().backupExpiryProperty());

        resetPasswordColumn.setCellFactory(param -> new TableCell<>() {
            private final Button btn = new Button("Reset");

            {
                btn.setOnAction(event -> {
                    AdminUser user = getTableView().getItems().get(getIndex());
                    handlePasswordReset(user);
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                if (empty) {
                    setGraphic(null);
                } else {
                    setGraphic(btn);
                }
            }
        });

        usersTable.setItems(userList);
        usersTable.setEditable(true);
    }

    private void loadUsers() {
        statusLabel.setText("Loading...");
        usersTable.setDisable(true);
        userList.clear();

        new Thread(() -> {
            try {
                JsonObject allUsers = SupabaseService.getInstance().getAllUsers();

                Platform.runLater(() -> {
                    for (Map.Entry<String, JsonElement> entry : allUsers.entrySet()) {
                        String uid = entry.getKey();
                        JsonObject userData = entry.getValue().getAsJsonObject();

                        // Extract Email if present, else fallback
                        String email = "No Email Saved";
                        if (userData.has("email")) {
                            email = userData.get("email").getAsString();
                        } else {
                            // Only show if missing
                            email = "Login to Update";
                        }

                        // Hide Admin from the list to prevent accidental lockout
                        if (email.equalsIgnoreCase("admin@gmail.com")) {
                            continue;
                        }

                        boolean ownership = false;
                        if (userData.has("ownership_payment")) {
                            ownership = userData.get("ownership_payment").getAsBoolean();
                        }

                        String ownershipExpiry = "N/A";
                        if (userData.has("ownership_expiry")) {
                            try {
                                long ts = userData.get("ownership_expiry").getAsLong();
                                if (ts > 0) {
                                    ownershipExpiry = sdf.format(new java.util.Date(ts));
                                } else if (ownership) {
                                    ownershipExpiry = "Lifetime/Manual";
                                }
                            } catch (Exception ignore) {
                            }
                        }

                        boolean backup = true;
                        if (userData.has("monthly_cloud_backup")) {
                            backup = userData.get("monthly_cloud_backup").getAsBoolean();
                        }

                        String backupExpiry = "N/A";
                        if (userData.has("backup_expiry")) {
                            try {
                                long ts = userData.get("backup_expiry").getAsLong();
                                if (ts > 0) {
                                    backupExpiry = sdf.format(new java.util.Date(ts));
                                } else if (backup) {
                                    backupExpiry = "Expired";
                                }
                            } catch (Exception ignore) {
                            }
                        }

                        String lastBackup = "Never";
                        if (userData.has("timestamp")) {
                            try {
                                long ts = userData.get("timestamp").getAsLong();
                                if (ts > 0) {
                                    lastBackup = sdf.format(new java.util.Date(ts));
                                }
                            } catch (Exception ignore) {
                            }
                        }

                        AdminUser user = new AdminUser(uid, email, ownership, ownershipExpiry, backup, backupExpiry,
                                lastBackup);

                        // Add listener for changes
                        user.ownershipProperty()
                                .addListener((obs, oldVal, newVal) -> {
                                    Map<String, Object> updates = new HashMap<>();
                                    updates.put("ownership_payment", newVal);
                                    if (newVal) {
                                        // Ownership is lifetime
                                        updates.put("ownership_expiry", 0);
                                        
                                        // Include first month of cloud backup
                                        updates.put("monthly_cloud_backup", true);
                                        long backupExp = System.currentTimeMillis() + (30L * 24 * 60 * 60 * 1000);
                                        updates.put("backup_expiry", backupExp);
                                        
                                        // Also update UI model instantly for backup
                                        user.backupProperty().set(true);
                                    } else {
                                        updates.put("ownership_expiry", 0);
                                    }
                                    updateUser(uid, updates);
                                });

                        user.backupProperty()
                                .addListener((obs, oldVal, newVal) -> {
                                    Map<String, Object> updates = new HashMap<>();
                                    updates.put("monthly_cloud_backup", newVal);
                                    if (newVal) {
                                        // Set 30-day expiry
                                        long expiry = System.currentTimeMillis() + (30L * 24 * 60 * 60 * 1000);
                                        updates.put("backup_expiry", expiry);
                                    } else {
                                        updates.put("backup_expiry", 0);
                                    }
                                    updateUser(uid, updates);
                                });

                        userList.add(user);
                    }

                    // Sort by Email
                    userList.sort(java.util.Comparator.comparing(u -> u.emailProperty().get().toLowerCase()));

                    statusLabel.setText("Loaded " + userList.size() + " users.");
                    usersTable.setDisable(false);
                });

            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> {
                    statusLabel.setText("Error: " + e.getMessage());
                    usersTable.setDisable(false);
                });
            }
        }).start();
    }

    private void updateUser(String uid, Map<String, Object> updates) {
        statusLabel.setText("Updating " + uid + "...");
        new Thread(() -> {
            try {
                SupabaseService.getInstance().adminUpdateUser(uid, updates);
                Platform.runLater(() -> statusLabel.setText("Updated user."));
            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> statusLabel.setText("Update Failed!"));
            }
        }).start();
    }

    private void handlePasswordReset(AdminUser user) {
        String email = user.emailProperty().get();
        if (email == null || email.isEmpty() || email.equals("No Email Saved") || email.equals("Login to Update")) {
            statusLabel.setText("Cannot reset: No valid email.");
            return;
        }

        statusLabel.setText("Sending reset email to " + email + "...");
        new Thread(() -> {
            try {
                boolean success = SupabaseService.getInstance().sendPasswordResetEmail(email,
                        "https://comforting-praline-1cf83a.netlify.app/");
                Platform.runLater(() -> {
                    if (success) {
                        statusLabel.setText("Reset email sent to " + email);
                    } else {
                        statusLabel.setText("Failed to send reset email.");
                    }
                });
            } catch (Exception e) {
                e.printStackTrace();
                Platform.runLater(() -> statusLabel.setText("Error sending email: " + e.getMessage()));
            }
        }).start();
    }

    // Quick Fix: Init fields for users with NULL data
    private void scanAndFix() {
        statusLabel.setText("Scanning...");
        new Thread(() -> {
            try {
                JsonObject allUsers = SupabaseService.getInstance().getAllUsers();
                int fixed = 0;
                for (Map.Entry<String, JsonElement> entry : allUsers.entrySet()) {
                    String uid = entry.getKey();
                    JsonObject userData = entry.getValue().getAsJsonObject();

                    Map<String, Object> updates = new HashMap<>();
                    boolean needsUpdate = false;

                    if (!userData.has("ownership_payment")) {
                        updates.put("ownership_payment", false);
                        needsUpdate = true;
                    }
                    if (!userData.has("monthly_cloud_backup")) {
                        updates.put("monthly_cloud_backup", true);
                        needsUpdate = true;
                    }

                    if (needsUpdate) {
                        SupabaseService.getInstance().adminUpdateUser(uid, updates);
                        fixed++;
                    }
                }
                final int count = fixed;
                Platform.runLater(() -> {
                    statusLabel.setText("Fixed " + count + " users.");
                    if (count > 0)
                        loadUsers();
                });
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }

    private void handleLogout() {
        try {
            com.meto.inventory.services.SupabaseService.getInstance().logout();
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Login.fxml"));
            Parent root = loader.load();
            Stage stage = (Stage) logoutButton.getScene().getWindow();
            stage.setScene(new Scene(root));
        } catch (Exception e) {
            e.printStackTrace();
            ((Stage) logoutButton.getScene().getWindow()).close();
        }
    }

    public static class AdminUser {
        private final StringProperty uid;
        private final StringProperty email;
        private final BooleanProperty ownership;
        private final StringProperty ownershipExpiry;
        private final BooleanProperty backup;
        private final StringProperty backupExpiry;
        private final StringProperty lastBackup;

        public AdminUser(String uid, String email, boolean ownership, String ownershipExpiry, boolean backup,
                String backupExpiry,
                String lastBackup) {
            this.uid = new SimpleStringProperty(uid);
            this.email = new SimpleStringProperty(email);
            this.ownership = new SimpleBooleanProperty(ownership);
            this.ownershipExpiry = new SimpleStringProperty(ownershipExpiry);
            this.backup = new SimpleBooleanProperty(backup);
            this.backupExpiry = new SimpleStringProperty(backupExpiry);
            this.lastBackup = new SimpleStringProperty(lastBackup);
        }

        public StringProperty uidProperty() {
            return uid;
        }

        public StringProperty emailProperty() {
            return email;
        }

        public BooleanProperty ownershipProperty() {
            return ownership;
        }

        public StringProperty ownershipExpiryProperty() {
            return ownershipExpiry;
        }

        public BooleanProperty backupProperty() {
            return backup;
        }

        public StringProperty lastBackupProperty() {
            return lastBackup;
        }

        public StringProperty backupExpiryProperty() {
            return backupExpiry;
        }
    }
}
