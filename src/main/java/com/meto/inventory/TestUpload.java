package com.meto.inventory;

public class TestUpload {
    public static void main(String[] args) throws Exception {
        DataManager.getInstance().switchDatabaseOnly("inventory_f91a785e_b4eb_4607_9e0d_920779bfd3a4.db");
        // We need to load session first!
        com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
        String token = service.loadSession();
        if (token != null) {
            System.out.println("Session loaded. Attempting login...");
            service.signInWithRefreshToken(token);
        } else {
            System.out.println("No session found.");
            return;
        }
        
        System.out.println("Forcing is_edited = 1...");
        DatabaseHelper db = DataManager.getInstance().getDbHelper();
        db.getConnection().createStatement().execute("UPDATE stock SET is_edited = 1");
        
        System.out.println("Uploading...");
        service.uploadDatabase(DataManager.getInstance().getCurrentDbName());
        System.out.println("Done.");
        System.exit(0);
    }
}
