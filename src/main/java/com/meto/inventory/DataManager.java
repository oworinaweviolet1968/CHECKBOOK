package com.meto.inventory;

import java.util.ArrayList;
import java.util.List;

public class DataManager {
    private static DataManager instance;
    private final DatabaseHelper dbHelper;
    private final List<DataChangeListener> listeners;

    private DataManager() {
        dbHelper = new DatabaseHelper();
        dbHelper.initializeDatabase();
        listeners = new ArrayList<>();
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

    public void addDataChangeListener(DataChangeListener listener) {
        listeners.add(listener);
    }

    public void removeDataChangeListener(DataChangeListener listener) {
        listeners.remove(listener);
    }

    public void notifyDataChanged() {
        for (DataChangeListener listener : listeners) {
            listener.onDataChanged();
        }
        triggerBackup();
    }

    private void triggerBackup() {
        if (com.meto.inventory.services.FirebaseService.getInstance().isLoggedIn()) {
            // Run in background to avoid freezing UI
            new Thread(() -> {
                try {
                    // Simple debounce or just run it.
                    // For better UX, we could verify hashing, but for now we upload.
                    com.meto.inventory.services.FirebaseService.getInstance().uploadDatabase("inventory.db");
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

    public interface DataChangeListener {
        void onDataChanged();
    }
}