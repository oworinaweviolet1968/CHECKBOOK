import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.meto.inventory.DatabaseHelper;

public class TestPush {
    public static void main(String[] args) throws Exception {
        DatabaseHelper db = new DatabaseHelper();
        db.setDatabaseName("inventory_f91a785e_b4eb_4607_9e0d_920779bfd3a4.db");
        db.initializeDatabase();
        
        JsonArray dirtyStock = db.getDirtyStock();
        System.out.println("Dirty stock size: " + dirtyStock.size());
        
        if (dirtyStock.size() > 0) {
            System.out.println(dirtyStock.toString());
        }
    }
}
