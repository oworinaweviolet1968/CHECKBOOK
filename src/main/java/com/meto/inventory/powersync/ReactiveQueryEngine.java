package com.meto.inventory.powersync;

import javafx.application.Platform;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

public class ReactiveQueryEngine {
    private static final Map<String, List<Runnable>> tableListeners = new ConcurrentHashMap<>();

    public static void subscribe(String tableName, Runnable callback) {
        tableListeners.computeIfAbsent(tableName, k -> new CopyOnWriteArrayList<>()).add(callback);
    }

    public static void unsubscribe(String tableName, Runnable callback) {
        List<Runnable> listeners = tableListeners.get(tableName);
        if (listeners != null) {
            listeners.remove(callback);
        }
    }

    public static void notifyTableChanged(String tableName) {
        List<Runnable> listeners = tableListeners.get(tableName);
        if (listeners != null && !listeners.isEmpty()) {
            for (Runnable callback : listeners) {
                if (Platform.isFxApplicationThread()) {
                    callback.run();
                } else {
                    Platform.runLater(callback);
                }
            }
        }
    }
}
