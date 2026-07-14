package com.meto.inventory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.lang.reflect.Field;

public class CheckSupa {
    public static void main(String[] args) throws Exception {
        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
        String token = service.loadSession();
        if (token != null) {
            service.signInWithRefreshToken(token);
            Field field = com.meto.inventory.services.SupabaseService.class.getDeclaredField("currentAccessToken");
            field.setAccessible(true);
            String accessToken = (String) field.get(service);
            
            String url = "https://jhucvkqwenhyiveqsmtf.supabase.co/rest/v1/stock?select=item,quantity";
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("apikey", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8")
                    .header("Authorization", "Bearer " + accessToken)
                    .GET()
                    .build();
            HttpClient client = HttpClient.newHttpClient();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            System.out.println("Supabase Stock Table: " + response.body());
        }
    }
}
