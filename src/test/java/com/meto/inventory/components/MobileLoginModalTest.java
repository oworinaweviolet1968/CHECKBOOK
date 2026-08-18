package com.meto.inventory.components;

import javafx.application.Platform;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class MobileLoginModalTest {

    @BeforeAll
    public static void initJFX() {
        try {
            Platform.startup(() -> {});
        } catch (IllegalStateException e) {
            // Toolkit already initialized
        }
    }

    @Test
    public void testModalInitialization() {
        Platform.runLater(() -> {
            MobileLoginModal modal = new MobileLoginModal(null, "user@test.com", new MobileLoginModal.LoginCallback() {
                @Override
                public void onSuccess(String refreshToken, String email) {}

                @Override
                public void onError(String message) {}
            });

            assertNotNull(modal, "MobileLoginModal instance should be created");
        });
    }
}
