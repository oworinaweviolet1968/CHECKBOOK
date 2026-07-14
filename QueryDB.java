import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

public class QueryDB {
    public static void main(String[] args) throws Exception {
        Connection conn = DriverManager.getConnection("jdbc:sqlite:inventory.db");
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery("SELECT item, quantity, unit, available_pieces FROM stock WHERE item LIKE '%Sugar%'");
        while (rs.next()) {
            System.out.printf("item=%s, quantity=%s, unit=%s, available_pieces=%s\n",
                rs.getString("item"), rs.getString("quantity"), rs.getString("unit"), rs.getString("available_pieces"));
        }
    }
}
