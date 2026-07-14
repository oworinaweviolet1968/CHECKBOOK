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

    public static NotificationService getInstance() {
        if (instance == null) {
            instance = new NotificationService();
        }
        return instance;
    }

    private void initFirebase() {
        try {
            if (FirebaseApp.getApps().isEmpty()) {
                InputStream serviceAccount = getClass().getResourceAsStream("/firebase-service-account.json");
                if (serviceAccount == null) {
                    LOGGER.severe("Firebase service account JSON not found in resources!");
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
            LOGGER.log(Level.SEVERE, "Failed to initialize Firebase Admin", e);
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
