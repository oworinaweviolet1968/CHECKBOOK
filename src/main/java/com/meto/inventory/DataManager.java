package com.meto.inventory;

import com.meto.inventory.services.NotificationService;
import com.meto.inventory.services.SupabaseService;

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

    public static synchronized DataManager getInstance() {
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
        if (userId == null || userId.trim().isEmpty() || "unknown_user".equalsIgnoreCase(userId.trim())) {
            System.out.println("GUARD: Refusing to switch database to empty/unauthenticated userId.");
            return;
        }
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
                if (getCurrentDbName().endsWith("inventory.db")) {
                    return; // Skip auto-sync if we are on the generic/unlogged database
                }

                SupabaseService service = SupabaseService.getInstance();
                boolean online = service.isOnline();

                // --- CONNECTIVITY TRANSITION NOTIFICATIONS ---
                if (wasOnline == null || wasOnline != online) {
                    if (online) {
                        javafx.application.Platform.runLater(() -> {
                            com.meto.inventory.utils.ToastService.showSuccess(
                                "Connection Restored",
                                "Desktop app is back online. Cloud sync will resume."
                            );
                        });
                    } else if (wasOnline != null) {
                        javafx.application.Platform.runLater(() -> {
                            com.meto.inventory.utils.ToastService.showWarning(
                                "Connection Lost",
                                "Desktop app is offline. Changes will sync when reconnected."
                            );
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
        }, 5, 15, TimeUnit.SECONDS);

    }

    private final java.util.Set<String> displayedToastKeys = java.util.Collections.synchronizedSet(new java.util.HashSet<>());

    private void checkAndDisplayNotifications() {
        if (dbHelper == null) return;
        java.util.List<DatabaseHelper.NotificationItem> notifs = dbHelper.getNotifications();
        long nowSec = System.currentTimeMillis() / 1000L;

        for (DatabaseHelper.NotificationItem notif : notifs) {
            if (notif.isRead() || !"Mobile".equals(notif.getSource())) {
                continue;
            }

            String notifKey = notif.getId() + "_" + notif.getMessage();

            // 1. Skip if toast was already rendered during this app session
            if (displayedToastKeys.contains(notifKey)) {
                dbHelper.markNotificationAsRead(notif.getId());
                continue;
            }

            // 2. Filter out stale actions (created > 5 minutes ago)
            boolean isStale = false;
            if (notif.getCreatedAt() != null && !notif.getCreatedAt().isEmpty()) {
                try {
                    String cleanDate = notif.getCreatedAt().replace("Z", "").replace(" ", "T");
                    java.time.LocalDateTime dt = java.time.LocalDateTime.parse(
                        cleanDate.length() >= 19 ? cleanDate.substring(0, 19) : cleanDate
                    );
                    long notifSec = dt.atZone(java.time.ZoneId.systemDefault()).toEpochSecond();
                    if ((nowSec - notifSec) > 300) { // > 5 minutes
                        isStale = true;
                    }
                } catch (Exception ignore) {
                }
            }

            // Mark key as seen and mark read in database
            displayedToastKeys.add(notifKey);
            dbHelper.markNotificationAsRead(notif.getId());

            // 3. Only render UI Toast for fresh (non-stale) mobile inputs
            if (!isStale) {
                javafx.application.Platform.runLater(() -> {
                    com.meto.inventory.utils.ToastService.showInfo(
                        "Mobile App Input",
                        notif.getMessage()
                    );
                });
                notifyDataChanged(false);
            }
        }
    }

    public interface DataChangeListener {
        void onDataChanged();
    }
}