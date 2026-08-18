package com.meto.inventory.components;

import com.meto.inventory.services.NotificationService;
import com.meto.inventory.services.SupabaseService;
import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.ProgressIndicator;
import javafx.scene.control.TextField;
import javafx.scene.effect.DropShadow;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.SVGPath;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.util.Duration;

import java.util.concurrent.atomic.AtomicBoolean;

public class MobileLoginModal {

    public interface LoginCallback {
        void onSuccess(String refreshToken, String email);
        void onError(String message);
    }

    private final Stage dialogStage;
    private final TextField emailInput;
    private final Label statusLabel;
    private final Label timerLabel;
    private final Button sendButton;
    private final Button cancelButton;
    private final VBox waitingBox;
    private final LoginCallback callback;

    private Timeline countdownTimeline;
    private int secondsRemaining = 60;
    private final AtomicBoolean isPollingActive = new AtomicBoolean(false);
    private String currentRequestId = null;

    public MobileLoginModal(Stage ownerStage, String initialEmail, LoginCallback callback) {
        this.callback = callback;
        this.dialogStage = new Stage();
        if (ownerStage != null) {
            this.dialogStage.initOwner(ownerStage);
        }
        this.dialogStage.initModality(Modality.APPLICATION_MODAL);
        this.dialogStage.initStyle(StageStyle.TRANSPARENT);

        // Card Container (Dark Slate #0F172A)
        VBox card = new VBox();
        card.setSpacing(20);
        card.setPadding(new Insets(28));
        card.setMaxWidth(440);
        card.setPrefWidth(440);
        card.setStyle(
            "-fx-background-color: #0F172A;" +
            "-fx-background-radius: 16px;" +
            "-fx-border-color: #1E293B;" +
            "-fx-border-radius: 16px;" +
            "-fx-border-width: 1px;"
        );

        DropShadow shadow = new DropShadow();
        shadow.setColor(Color.rgb(0, 0, 0, 0.45));
        shadow.setRadius(24);
        shadow.setOffsetY(8);
        card.setEffect(shadow);

        // Header: Badge Icon + Title + Subtitle
        StackPane iconBadge = new StackPane();
        Circle bgCircle = new Circle(24, Color.web("#132E2B"));
        SVGPath phoneIcon = new SVGPath();
        phoneIcon.setContent("M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z");
        phoneIcon.setFill(Color.web("#00D09C"));
        iconBadge.getChildren().addAll(bgCircle, phoneIcon);
        iconBadge.setAlignment(Pos.CENTER);

        VBox headerText = new VBox(6);
        Label titleLabel = new Label("Login via Mobile App");
        titleLabel.setStyle("-fx-font-size: 18pt; -fx-font-weight: bold; -fx-text-fill: #FFFFFF;");

        Label subtitleLabel = new Label("Enter your registered email to send an instant sign-in request to your phone.");
        subtitleLabel.setWrapText(true);
        subtitleLabel.setStyle("-fx-font-size: 11pt; -fx-text-fill: #94A3B8;");

        headerText.getChildren().addAll(titleLabel, subtitleLabel);

        VBox headerBox = new VBox(14, iconBadge, headerText);
        headerBox.setAlignment(Pos.TOP_LEFT);

        // Input Field Section
        VBox inputSection = new VBox(8);
        Label inputLabel = new Label("Registered Email Address");
        inputLabel.setStyle("-fx-font-size: 10.5pt; -fx-text-fill: #94A3B8; -fx-font-weight: bold;");

        emailInput = new TextField();
        emailInput.setPromptText("e.g. meto@meto.com");
        if (initialEmail != null && !initialEmail.trim().isEmpty()) {
            emailInput.setText(initialEmail.trim());
        }

        String normalInputStyle =
            "-fx-background-color: #1E293B;" +
            "-fx-text-fill: #FFFFFF;" +
            "-fx-prompt-text-fill: #64748B;" +
            "-fx-border-color: #334155;" +
            "-fx-border-radius: 8px;" +
            "-fx-background-radius: 8px;" +
            "-fx-padding: 12px;" +
            "-fx-font-size: 11.5pt;";

        String focusedInputStyle =
            "-fx-background-color: #1E293B;" +
            "-fx-text-fill: #FFFFFF;" +
            "-fx-prompt-text-fill: #64748B;" +
            "-fx-border-color: #00D09C;" +
            "-fx-border-radius: 8px;" +
            "-fx-background-radius: 8px;" +
            "-fx-padding: 12px;" +
            "-fx-font-size: 11.5pt;";

        emailInput.setStyle(normalInputStyle);
        emailInput.focusedProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal) {
                emailInput.setStyle(focusedInputStyle);
            } else {
                emailInput.setStyle(normalInputStyle);
            }
        });

        statusLabel = new Label();
        statusLabel.setWrapText(true);
        statusLabel.setStyle("-fx-font-size: 10.5pt; -fx-text-fill: #EF4444;");
        statusLabel.setManaged(false);
        statusLabel.setVisible(false);

        inputSection.getChildren().addAll(inputLabel, emailInput, statusLabel);

        // Live Waiting Section (Spinner + Status + Countdown Timer)
        ProgressIndicator spinner = new ProgressIndicator();
        spinner.setPrefSize(26, 26);
        spinner.setMaxSize(26, 26);
        spinner.setStyle("-fx-progress-color: #00D09C;");

        Label waitingText = new Label("Waiting for mobile approval...");
        waitingText.setStyle("-fx-font-size: 11.5pt; -fx-text-fill: #F8FAFC; -fx-font-weight: bold;");

        timerLabel = new Label("60s remaining");
        timerLabel.setStyle("-fx-font-size: 10pt; -fx-text-fill: #94A3B8;");

        VBox waitingTextGroup = new VBox(3, waitingText, timerLabel);
        HBox spinnerRow = new HBox(12, spinner, waitingTextGroup);
        spinnerRow.setAlignment(Pos.CENTER_LEFT);

        waitingBox = new VBox(12, spinnerRow);
        waitingBox.setStyle(
            "-fx-background-color: #1E293B;" +
            "-fx-background-radius: 10px;" +
            "-fx-padding: 14px;" +
            "-fx-border-color: rgba(0, 208, 156, 0.4);" +
            "-fx-border-radius: 10px;"
        );
        waitingBox.setVisible(false);
        waitingBox.setManaged(false);

        // Action Buttons
        sendButton = new Button("Send Authorization Request");
        sendButton.setMaxWidth(Double.MAX_VALUE);
        sendButton.setStyle(
            "-fx-background-color: #00D09C;" +
            "-fx-text-fill: #FFFFFF;" +
            "-fx-font-weight: bold;" +
            "-fx-font-size: 11.5pt;" +
            "-fx-padding: 12px 18px;" +
            "-fx-background-radius: 8px;" +
            "-fx-cursor: hand;"
        );
        sendButton.setOnAction(e -> startAuthorizationFlow());

        cancelButton = new Button("Cancel");
        cancelButton.setMaxWidth(Double.MAX_VALUE);
        cancelButton.setStyle(
            "-fx-background-color: transparent;" +
            "-fx-text-fill: #94A3B8;" +
            "-fx-font-size: 11pt;" +
            "-fx-padding: 10px 16px;" +
            "-fx-border-color: #334155;" +
            "-fx-border-radius: 8px;" +
            "-fx-background-radius: 8px;" +
            "-fx-cursor: hand;"
        );
        cancelButton.setOnAction(e -> closeAndCleanup());

        HBox buttonBox = new HBox(12, cancelButton, sendButton);
        HBox.setHgrow(sendButton, Priority.ALWAYS);
        HBox.setHgrow(cancelButton, Priority.ALWAYS);

        card.getChildren().addAll(headerBox, inputSection, waitingBox, buttonBox);

        // Dark Semi-Transparent Overlay
        StackPane rootPane = new StackPane(card);
        rootPane.setPadding(new Insets(24));
        rootPane.setStyle("-fx-background-color: rgba(15, 23, 42, 0.75);");

        Scene scene = new Scene(rootPane);
        scene.setFill(Color.TRANSPARENT);

        dialogStage.setScene(scene);
        dialogStage.setOnCloseRequest(e -> closeAndCleanup());
    }

    public void show() {
        dialogStage.centerOnScreen();
        dialogStage.show();
    }

    private void startAuthorizationFlow() {
        String email = emailInput.getText().trim();
        if (email.isEmpty() || !email.contains("@")) {
            showError("Please enter a valid registered email address.");
            return;
        }

        hideError();
        setWaitingState(true);

        secondsRemaining = 60;
        timerLabel.setText("60s remaining");

        if (countdownTimeline != null) {
            countdownTimeline.stop();
        }

        countdownTimeline = new Timeline(new KeyFrame(Duration.seconds(1), ev -> {
            secondsRemaining--;
            if (secondsRemaining > 0) {
                timerLabel.setText(secondsRemaining + "s remaining");
            } else {
                timerLabel.setText("Expired");
                stopPollingAndFail("Login request timed out after 60 seconds.");
            }
        }));
        countdownTimeline.setCycleCount(60);
        countdownTimeline.play();

        isPollingActive.set(true);

        new Thread(() -> {
            try {
                SupabaseService service = SupabaseService.getInstance();
                currentRequestId = service.createLoginRequest(email);

                // Dispatch FCM notification to notify the mobile app
                try {
                    NotificationService.getInstance().sendAppUpdateNotification(
                        "Login Approval Request",
                        "Desktop login request initiated for " + email
                    );
                } catch (Exception ignored) {}

                while (isPollingActive.get() && secondsRemaining > 0) {
                    com.google.gson.JsonObject request = service.pollLoginRequest(currentRequestId);
                    if (request != null) {
                        String status = request.get("status").getAsString();
                        if ("approved".equals(status)) {
                            String refreshToken = null;
                            if (request.has("refresh_token") && !request.get("refresh_token").isJsonNull()) {
                                refreshToken = request.get("refresh_token").getAsString();
                            }

                            if (refreshToken != null && !refreshToken.trim().isEmpty()) {
                                String finalToken = refreshToken;
                                Platform.runLater(() -> {
                                    stopCountdown();
                                    isPollingActive.set(false);
                                    cleanupRequest();
                                    dialogStage.close();
                                    if (callback != null) {
                                        callback.onSuccess(finalToken, email);
                                    }
                                });
                                return;
                            }
                        } else if ("rejected".equals(status)) {
                            Platform.runLater(() -> stopPollingAndFail("Login request was rejected on your mobile device."));
                            return;
                        }
                    }
                    Thread.sleep(2000);
                }
            } catch (Exception ex) {
                ex.printStackTrace();
                Platform.runLater(() -> stopPollingAndFail("Mobile login error: " + ex.getMessage()));
            }
        }).start();
    }

    private void stopPollingAndFail(String errorMsg) {
        isPollingActive.set(false);
        stopCountdown();
        cleanupRequest();
        setWaitingState(false);
        showError(errorMsg);
        if (callback != null) {
            callback.onError(errorMsg);
        }
    }

    private void stopCountdown() {
        if (countdownTimeline != null) {
            countdownTimeline.stop();
        }
    }

    private void cleanupRequest() {
        if (currentRequestId != null) {
            String reqId = currentRequestId;
            currentRequestId = null;
            new Thread(() -> SupabaseService.getInstance().deleteLoginRequest(reqId)).start();
        }
    }

    private void closeAndCleanup() {
        isPollingActive.set(false);
        stopCountdown();
        cleanupRequest();
        dialogStage.close();
    }

    private void setWaitingState(boolean waiting) {
        emailInput.setDisable(waiting);
        sendButton.setDisable(waiting);
        waitingBox.setVisible(waiting);
        waitingBox.setManaged(waiting);
    }

    private void showError(String msg) {
        statusLabel.setText(msg);
        statusLabel.setVisible(true);
        statusLabel.setManaged(true);
    }

    private void hideError() {
        statusLabel.setText("");
        statusLabel.setVisible(false);
        statusLabel.setManaged(false);
    }
}
