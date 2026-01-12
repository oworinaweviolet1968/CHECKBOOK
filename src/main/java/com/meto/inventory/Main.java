package com.meto.inventory;

import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;

public class Main extends Application {
    @Override
    public void start(Stage primaryStage) throws Exception {
        FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Main.fxml"));
        Parent root = loader.load();
        Scene scene = new Scene(root, 1200, 720);
        scene.getStylesheets().add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());

        primaryStage.setTitle("Inventory Management System");
        primaryStage.setScene(scene);
        primaryStage.show();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
