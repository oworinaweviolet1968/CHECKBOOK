package com.meto.inventory.components;

import javafx.scene.Group;
import javafx.scene.paint.Color;
import javafx.scene.shape.*;


import javafx.scene.layout.Region;

/**
 * BellIcon — draws a notification bell in JavaFX using SVG paths.
 *
 * Usage:
 *   Region bell = BellIcon.create(64, Color.BLACK);
 *   Region bell = BellIcon.create(48, Color.web("#3B82F6"));
 */
public class BellIcon {

    private BellIcon() {}

    public static Region create(double size, Color color) {
        double s = size / 512.0; // scale factor from 512-unit design space

        // ── Bell body path ───────────────────────────────────────────────────
        // Large rounded dome shape with flared bottom skirt
        SVGPath body = new SVGPath();
        body.setContent(
            "M 256 480 " +
            "C 220 480 190 455 183 422 " +
            "L 329 422 " +
            "C 322 455 292 480 256 480 Z " +   // clapper arc (bottom semicircle)

            "M 88 390 " +
            "C 66 390 52 374 52 354 " +
            "C 52 344 56 335 63 328 " +
            "C 90 302 108 267 108 228 " +
            "L 108 210 " +
            "C 108 130 175 64 256 64 " +
            "C 337 64 404 130 404 210 " +
            "L 404 228 " +
            "C 404 267 422 302 449 328 " +
            "C 456 335 460 344 460 354 " +
            "C 460 374 446 390 424 390 " +
            "Z"
        );
        body.setFill(Color.TRANSPARENT);
        body.setStroke(color);
        body.setStrokeWidth(36);
        body.setStrokeLineJoin(StrokeLineJoin.ROUND);
        body.setStrokeLineCap(StrokeLineCap.ROUND);

        // ── Hanger (small circle at top) ─────────────────────────────────────
        Circle hanger = new Circle(256, 38, 20);
        hanger.setFill(Color.TRANSPARENT);
        hanger.setStroke(color);
        hanger.setStrokeWidth(30);

        // ── Clapper (bottom half-circle opening) ─────────────────────────────
        Arc clapper = new Arc(256, 422, 52, 52, 0, -180);
        clapper.setType(ArcType.OPEN);
        clapper.setFill(Color.TRANSPARENT);
        clapper.setStroke(color);
        clapper.setStrokeWidth(30);
        clapper.setStrokeLineCap(StrokeLineCap.ROUND);

        Group g = new Group(body, hanger, clapper);
        g.getTransforms().add(new javafx.scene.transform.Scale(s, s, 0, 0));

        javafx.scene.layout.Pane container = new javafx.scene.layout.Pane() {
            @Override
            protected double computePrefWidth(double height) { return size; }
            @Override
            protected double computePrefHeight(double width) { return size; }
            @Override
            protected double computeMinWidth(double height) { return size; }
            @Override
            protected double computeMinHeight(double width) { return size; }
            @Override
            protected double computeMaxWidth(double height) { return size; }
            @Override
            protected double computeMaxHeight(double width) { return size; }
        };
        container.getChildren().add(g);
        return container;
    }

    // Convenience: black bell
    public static Region create(double size) {
        return create(size, Color.BLACK);
    }
}
