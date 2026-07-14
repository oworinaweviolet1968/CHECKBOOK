package com.meto.inventory;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class DataManager {
    private static DataManager instance;
    private final DatabaseHelper dbHelper;
    private final List<DataChangeListener> listeners;

    private DataManager() {
        dbHelper = new DatabaseHelper();
        dbHelper.initializeDatabase();
        listeners = new ArrayList<>();
        startAutoSyncTask();
    }

    public static DataManager getInstance() {
        if (instance == null) {
            instance = new DataManager();
        }
        return instance;
    }

    public DatabaseHelper getDbHelper() {
        return dbHelper;
    }

    public void resetDatabase(String userId) {
        switchDatabaseOnly(userId);
        // FORCE a refresh of all data listeners (UI)
        notifyDataChanged();
    }

    public void switchDatabaseOnly(String userId) {
        // Sanitize userId just in case (e.g. email or uuid)
        String cleanId = userId.replaceAll("[^a-zA-Z0-9]", "_");
        String dbName = "inventory_" + cleanId + ".db";
        System.out.println("Switching database to: " + dbName);
        dbHelper.setDatabaseName(dbName);
    }

    public String getCurrentDbName() {
        return dbHelper.getCurrentDbName();
    }

    public void addDataChangeListener(DataChangeListener listener) {
        listeners.add(listener);
    }

    public void removeDataChangeListener(DataChangeListener listener) {
        listeners.remove(listener);
    }

    public void notifyDataChanged() {
        notifyDataChanged(true);
    }

    public void notifyDataChanged(boolean triggerBackup) {
        for (DataChangeListener listener : listeners) {
            listener.onDataChanged();
        }
        if (triggerBackup) {
            triggerBackup();
        }
    }

    private boolean isBackupEnabled = true;

    public void setBackupEnabled(boolean enabled) {
        this.isBackupEnabled = enabled;
    }

    public boolean isBackupEnabled() {
        return isBackupEnabled;
    }

    private void triggerBackup() {
        if (!isBackupEnabled) {
            System.out.println("Backup skipped: Subscription required.");
            return;
        }
        if (com.meto.inventory.services.SupabaseService.getInstance().isLoggedIn()) {
            // Run in background to avoid freezing UI
            new Thread(() -> {
                try {
                    // SAFEGUARD POINTER:
                    // Do NOT upload if the database is empty.
                    // This prevents overwriting the cloud backup when switching to a fresh DB file
                    // on login.
                    if (!dbHelper.hasData()) {
                        System.out.println("Backup skipped: Local database is empty.");
                        return;
                    }

                    // Simple debounce or just run it.
                    // For better UX, we could verify hashing, but for now we upload.
                    com.meto.inventory.services.SupabaseService.getInstance().uploadDatabase(getCurrentDbName(), true);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }).start();
        }
    }

    // In DataManager class
    public void notifyItemsChanged() {
        notifyDataChanged(); // This will refresh everything including items
    }

    private ScheduledExecutorService syncExecutor;

    private void startAutoSyncTask() {
        if (syncExecutor != null) return;
        
        syncExecutor = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "AutoSyncThread");
            t.setDaemon(true);
            return t;
        });

        // Run every 10 seconds as requested
        syncExecutor.scheduleAtFixedRate(() -> {
            try {
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
                
                if (service.isLoggedIn() && isBackupEnabled) {
                    boolean online = service.isOnline();
                    if (online) {
                            if (service.isSyncFailed()) {
                                System.out.println("AutoSync: Connection restored. Retrying upload...");
                                String savedToken = service.loadSession();
                                if (savedToken != null) {
                                    try { service.signInWithRefreshToken(savedToken); } 
                                    catch (Exception ex) {}
                                }
                                service.uploadDatabase(getCurrentDbName(), true);
                            } else {
                                // Online: Poll for any new changes from mobile app
                                boolean downloaded = service.syncOnLogin(getCurrentDbName(), true, false);
                                if (downloaded) {
                                    notifyDataChanged();
                                }
                                service.notifyStatus("Cloud: Synced");
                            }
                            
                            // Check for unread notifications
                            checkAndDisplayNotifications();
                        } else {
                        // Offline
                        service.notifyStatus("Cloud: Offline");
                    }
                }
            } catch (Exception e) {
                // Silently ignore background sync errors to avoid UI popups
            }
        }, 10, 10, TimeUnit.SECONDS);
    }

    private void checkAndDisplayNotifications() {
        if (dbHelper == null) return;
        java.util.List<DatabaseHelper.NotificationItem> notifs = dbHelper.getNotifications();
        for (DatabaseHelper.NotificationItem notif : notifs) {
            if (!notif.isRead() && "Mobile".equals(notif.getSource())) {
                javafx.application.Platform.runLater(() -> {
                    org.controlsfx.control.Notifications.create()
                        .title("Mobile App Input")
                        .text(notif.getMessage())
                        .position(javafx.geometry.Pos.TOP_RIGHT)
                        .showInformation();
                });
                dbHelper.markNotificationAsRead(notif.getId());
                // Notify UI to refresh Notifications view
                notifyDataChanged(false); 
            }
        }
    }

    public interface DataChangeListener {
        void onDataChanged();
    }
}