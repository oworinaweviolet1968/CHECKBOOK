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
                    com.meto.inventory.services.SupabaseService.getInstance().uploadDatabase(getCurrentDbName());
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

        // Run every 30 seconds as requested
        syncExecutor.scheduleAtFixedRate(() -> {
            try {
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
                
                if (service.isLoggedIn() && isBackupEnabled && service.isSyncFailed()) {
                    if (service.isOnline()) {
                        System.out.println("AutoSync: Connection restored. Retrying upload...");
                        service.uploadDatabase(getCurrentDbName());
                    }
                }
            } catch (Exception e) {
                // Silently ignore background sync errors to avoid UI popups
            }
        }, 30, 30, TimeUnit.SECONDS);
    }

    public interface DataChangeListener {
        void onDataChanged();
    }
}