package com.meto.inventory.components;

import javafx.animation.KeyFrame;
import javafx.animation.KeyValue;
import javafx.animation.Timeline;
import javafx.geometry.Pos;
import javafx.scene.layout.StackPane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.util.Duration;

public class LoadingBar extends StackPane {

    private static final Color TRACK_COLOR = Color.web("#DBEAFE"); // blue-100
    private static final Color BAR_COLOR   = Color.web("#3B82F6"); // blue-500
    private static final double DURATION   = 1200; // ms per cycle

    private final Rectangle fill;
    private final Timeline  timeline;
    private final double    barWidth;

    public LoadingBar() {
        this(200, 4);
    }

    public LoadingBar(double width, double height) {
        this.barWidth = width;

        double radius = height / 2;

        // Track
        Rectangle track = new Rectangle(width, height);
        track.setArcWidth(radius * 2);
        track.setArcHeight(radius * 2);
        track.setFill(TRACK_COLOR);

        // Moving fill — starts at 40% of total width
        double fillW = width * 0.4;
        fill = new Rectangle(fillW, height);
        fill.setArcWidth(radius * 2);
        fill.setArcHeight(radius * 2);
        fill.setFill(BAR_COLOR);

        // Position fill via translateX; StackPane centres everything by default
        // so we offset from centre: leftmost = -(width/2 - fillW/2)
        double leftEdge  = -(width / 2 - fillW / 2);
        double rightEdge =  (width / 2 - fillW / 2);

        getChildren().addAll(track, fill);
        setAlignment(Pos.CENTER_LEFT);
        setPrefSize(width, height);
        setMaxSize(width, height);

        // Slide left → right → left (indeterminate bounce)
        timeline = new Timeline(
            new KeyFrame(Duration.ZERO,
                new KeyValue(fill.translateXProperty(), leftEdge,
                             javafx.animation.Interpolator.EASE_IN)),
            new KeyFrame(Duration.millis(DURATION * 0.5),
                new KeyValue(fill.translateXProperty(), rightEdge,
                             javafx.animation.Interpolator.EASE_OUT)),
            new KeyFrame(Duration.millis(DURATION),
                new KeyValue(fill.translateXProperty(), leftEdge,
                             javafx.animation.Interpolator.EASE_IN))
        );
        timeline.setCycleCount(Timeline.INDEFINITE);
    }

    public void start() {
        setVisible(true);
        setManaged(true);
        timeline.play();
    }

    public void stop() {
        timeline.stop();
        fill.setTranslateX(0);
        setVisible(false);
        setManaged(false);
    }
}
