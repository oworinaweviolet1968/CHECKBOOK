package com.meto.inventory.services;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import java.io.InputStream;
import java.util.logging.Level;
import java.util.logging.Logger;

public class NotificationService {
    private static final Logger LOGGER = Logger.getLogger(NotificationService.class.getName());
    private static NotificationService instance;
    private boolean isInitialized = false;

    private NotificationService() {
        initFirebase();
    }

    public static synchronized NotificationService getInstance() {
        if (instance == null) {
            instance = new NotificationService();
        }
        return instance;
    }

    private void initFirebase() {
        try {
            if (FirebaseApp.getApps().isEmpty()) {
                InputStream serviceAccount = null;

                // 1. Check environment variable GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_CONFIG_PATH
                String envPath = System.getenv("GOOGLE_APPLICATION_CREDENTIALS");
                if (envPath == null || envPath.isBlank()) {
                    envPath = System.getenv("FIREBASE_CONFIG_PATH");
                }

                if (envPath != null && !envPath.isBlank()) {
                    java.io.File file = new java.io.File(envPath);
                    if (file.exists()) {
                        serviceAccount = new java.io.FileInputStream(file);
                        LOGGER.info("Loading Firebase credentials from environment path: " + envPath);
                    }
                }

                // 2. Check user data folder (~/METO_IMS_DATA/firebase-service-account.json)
                if (serviceAccount == null) {
                    String userHome = System.getProperty("user.home");
                    java.io.File localConfig = new java.io.File(userHome, "METO_IMS_DATA/firebase-service-account.json");
                    if (localConfig.exists()) {
                        serviceAccount = new java.io.FileInputStream(localConfig);
                        LOGGER.info("Loading Firebase credentials from local data folder.");
                    }
                }

                // 3. Fallback to classpath resource if present
                if (serviceAccount == null) {
                    serviceAccount = getClass().getResourceAsStream("/firebase-service-account.json");
                }

                if (serviceAccount == null) {
                    LOGGER.warning("Firebase service account JSON not configured. Desktop notifications disabled.");
                    return;
                }

                FirebaseOptions options = FirebaseOptions.builder()
                        .setCredentials(GoogleCredentials.fromStream(serviceAccount))
                        .build();

                FirebaseApp.initializeApp(options);
                isInitialized = true;
                LOGGER.info("Firebase Admin initialized successfully.");
            } else {
                isInitialized = true;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Firebase Admin initialization skipped/failed", e);
        }
    }

    public void sendDesktopActionNotification(String title, String body) {
        sendNotificationToTopic("desktop_actions", title, body);
    }

    public void sendAppUpdateNotification(String title, String body) {
        sendNotificationToTopic("app_updates", title, body);
    }

    private void sendNotificationToTopic(String topic, String title, String body) {
        if (!isInitialized) {
            LOGGER.warning("Firebase is not initialized. Cannot send notification.");
            return;
        }

        new Thread(() -> {
            try {
                Notification notification = Notification.builder()
                        .setTitle(title)
                        .setBody(body)
                        .build();

                Message message = Message.builder()
                        .setNotification(notification)
                        .setTopic(topic)
                        .build();

                String response = FirebaseMessaging.getInstance().send(message);
                LOGGER.info("Successfully sent message to topic " + topic + ": " + response);
            } catch (FirebaseMessagingException e) {
                LOGGER.log(Level.SEVERE, "Failed to send FCM message", e);
            }
        }).start();
    }
}
