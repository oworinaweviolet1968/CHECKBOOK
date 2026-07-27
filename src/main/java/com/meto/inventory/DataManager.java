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
            if (javafx.application.Platform.isFxApplicationThread()) {
                listener.onDataChanged();
            } else {
                javafx.application.Platform.runLater(listener::onDataChanged);
            }
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
    // Track previous online state to detect transitions
    private Boolean wasOnline = null;
    private long lastCloudSyncTime = 0;

    private void startAutoSyncTask() {
        if (syncExecutor != null) return;
        
        syncExecutor = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "AutoSyncThread");
            t.setDaemon(true);
            return t;
        });

        // Run background sync check every 15 seconds to prevent network/DB locks and UI lag
        syncExecutor.scheduleAtFixedRate(() -> {
            try {
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
                boolean online = service.isOnline();

                // --- CONNECTIVITY TRANSITION NOTIFICATIONS ---
                if (wasOnline == null || wasOnline != online) {
                    if (online) {
                        com.meto.inventory.services.NotificationService.getInstance()
                            .sendDesktopActionNotification("Desktop App Online", "Desktop app accessed the internet and is now online.");
                        
                        javafx.application.Platform.runLater(() -> {
                            org.controlsfx.control.Notifications.create()
                                .title("🟢 Connection Restored")
                                .text("Desktop app is back online. Cloud sync will resume.")
                                .position(javafx.geometry.Pos.TOP_RIGHT)
                                .showInformation();
                        });
                    } else if (wasOnline != null) {
                        javafx.application.Platform.runLater(() -> {
                            org.controlsfx.control.Notifications.create()
                                .title("🔴 Connection Lost")
                                .text("Desktop app is offline. Changes will sync when reconnected.")
                                .position(javafx.geometry.Pos.TOP_RIGHT)
                                .showWarning();
                        });
                    }
                }
                wasOnline = online;

                int pendingCount = dbHelper.getPendingSyncCount();
                if (!online) {
                    // Offline state
                    service.notifyStatus(pendingCount > 0 ? "Cloud: Offline (" + pendingCount + " pending)" : "Cloud: Offline");
                } else {
                    // Online state
                    service.notifyStatus(pendingCount > 0 ? "Cloud: " + pendingCount + " pending" : "Cloud: Synced");

                    if (service.isLoggedIn() && isBackupEnabled) {
                        long now = System.currentTimeMillis();
                        if (now - lastCloudSyncTime >= 45000 || service.isSyncFailed()) {
                            lastCloudSyncTime = now;
                            service.updateHeartbeat();

                            if (service.isSyncFailed()) {
                                System.out.println("AutoSync: Connection restored. Retrying upload...");
                                String savedToken = service.loadSession();
                                if (savedToken != null) {
                                    try { service.signInWithRefreshToken(savedToken); } 
                                    catch (Exception ex) {}
                                }
                            }
                            // Always push local dirty changes first, then pull updates from cloud
                            service.uploadDatabase(getCurrentDbName(), true);
                            boolean downloaded = service.syncOnLogin(getCurrentDbName(), true, false);
                            if (downloaded) {
                                notifyDataChanged(false);
                            }
                        }
                        
                        // Check for unread notifications
                        checkAndDisplayNotifications();
                    }
                }
            } catch (Exception e) {
                // Silently ignore background sync errors to avoid UI popups
            }
        }, 0, 15, TimeUnit.SECONDS);

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