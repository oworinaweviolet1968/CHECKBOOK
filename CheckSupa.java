package com.meto.inventory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public class CheckSupa {
    public static void main(String[] args) throws Exception {
        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
        String token = service.loadSession();
        if (token != null) {
            service.signInWithRefreshToken(token);
            String url = "https://jhucvkqwenhyiveqsmtf.supabase.co/rest/v1/stock?select=item,quantity";
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("apikey", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8")
                    // Note: need access token to bypass RLS! 
                    // How to get access token? We can just use reflection or since we are in the same package we can't...
                    // Wait, signInWithRefreshToken(token) updates the session.
                    // We can just call service.getAllUsers() to test, but we need stock.
                    // Let's use `syncOnLogin` to fetch it to our local db! No wait.
            System.exit(0);
        }
    }
}
