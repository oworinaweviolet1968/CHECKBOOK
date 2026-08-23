package com.meto.inventory.controllers;

import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import java.util.*;

/**
 * Spring Boot REST Controller for Pesapal v3 Server-to-Server Payment Integration.
 */
@RestController
@RequestMapping("/api/payments")
@CrossOrigin(origins = "*")
public class PesapalPaymentController {

    private static final String BASE_URL = "https://pay.pesapal.com/v3";
    private static final String CONSUMER_KEY = "TDpigBOOhs+zAl8cwH2Fl82jJGyD8xev";
    private static final String CONSUMER_SECRET = "1KpqkfsMaihIcOlhnBo/gBZ5smw=";
    private static final String IPN_ID = "6a860413-dd1e-4429-802d-da01adada02d";
    private static final String CALLBACK_URL = "https://checkbook.co.ug/#/payment/callback";

    private String cachedToken = null;
    private long tokenExpiryTime = 0;

    /**
     * 1. OAuth2 Token Management (with in-memory caching)
     */
    private synchronized String getAuthToken() {
        long now = System.currentTimeMillis();
        if (cachedToken != null && tokenExpiryTime > now + 30000) {
            return cachedToken;
        }

        RestTemplate restTemplate = new RestTemplate();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, String> body = new HashMap<>();
        body.put("consumer_key", CONSUMER_KEY);
        body.put("consumer_secret", CONSUMER_SECRET);

        HttpEntity<Map<String, String>> entity = new HttpEntity<>(body, headers);
        @SuppressWarnings("rawtypes")
        ResponseEntity<Map> response = restTemplate.postForEntity(BASE_URL + "/api/Auth/RequestToken", entity, Map.class);

        if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
            cachedToken = (String) response.getBody().get("token");
            tokenExpiryTime = now + (300 * 1000); // 5 minute validity
            return cachedToken;
        }
        throw new RuntimeException("Failed to acquire Pesapal Auth Token.");
    }

    /**
     * 2. Order Initiation Endpoint (POST /api/payments/initiate)
     */
    @PostMapping("/initiate")
    public ResponseEntity<Map<String, Object>> initiatePayment(@RequestBody Map<String, Object> request) {
        try {
            String token = getAuthToken();
            String amount = String.valueOf(request.get("amount"));
            String phone = String.valueOf(request.get("phoneNumber"));
            String email = String.valueOf(request.get("email"));
            String itemType = String.valueOf(request.getOrDefault("itemType", "ownership"));

            String merchantRef = "CB-" + itemType.toUpperCase() + "-" + System.currentTimeMillis();
            String trackingId = "PESA-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
            String fullCallback = CALLBACK_URL + "?OrderTrackingId=" + trackingId + "&OrderMerchantReference=" + merchantRef;

            Map<String, Object> billingAddress = new HashMap<>();
            billingAddress.put("email_address", email);
            billingAddress.put("phone_number", phone);
            billingAddress.put("first_name", "Valued");
            billingAddress.put("last_name", "Customer");

            Map<String, Object> orderPayload = new HashMap<>();
            orderPayload.put("id", merchantRef);
            orderPayload.put("currency", "UGX");
            orderPayload.put("amount", Double.parseDouble(amount));
            orderPayload.put("description", "CheckBook " + itemType);
            orderPayload.put("callback_url", fullCallback);
            orderPayload.put("notification_id", IPN_ID);
            orderPayload.put("billing_address", billingAddress);

            RestTemplate restTemplate = new RestTemplate();
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth(token);

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(orderPayload, headers);
            @SuppressWarnings("rawtypes")
            ResponseEntity<Map> response = restTemplate.postForEntity(BASE_URL + "/api/Transactions/SubmitOrderRequest", entity, Map.class);

            Map<String, Object> result = new HashMap<>();
            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                result.put("success", true);
                result.put("redirect_url", response.getBody().get("redirect_url"));
                result.put("order_tracking_id", response.getBody().get("order_tracking_id"));
                result.put("merchant_reference", merchantRef);
                return ResponseEntity.ok(result);
            }
            result.put("success", false);
            result.put("error", "Order request rejected by Pesapal.");
            return ResponseEntity.badRequest().body(result);
        } catch (Exception e) {
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("success", false);
            errorMap.put("error", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorMap);
        }
    }

    /**
     * 3. IPN Webhook Listener (GET/POST /api/payments/webhook/pesapal)
     */
    @RequestMapping(value = "/webhook/pesapal", method = {RequestMethod.GET, RequestMethod.POST})
    public ResponseEntity<Map<String, Object>> handleIpnWebhook(
            @RequestParam(name = "OrderTrackingId", required = false) String trackingId,
            @RequestParam(name = "OrderMerchantReference", required = false) String merchantRef) {

        Map<String, Object> response = new HashMap<>();
        if (trackingId == null || trackingId.isEmpty()) {
            response.put("error", "Missing OrderTrackingId");
            return ResponseEntity.badRequest().body(response);
        }

        // Query status from Pesapal
        String status = getTransactionStatus(trackingId);
        System.out.println("[Pesapal IPN] TrackingId: " + trackingId + " | Status: " + status);

        response.put("orderNotificationType", "IPNCHANGE");
        response.put("orderTrackingId", trackingId);
        response.put("orderMerchantReference", merchantRef);
        response.put("status", 200);
        return ResponseEntity.ok(response);
    }

    /**
     * 4. Query Transaction Status (GET /api/payments/status/{trackingId})
     */
    @GetMapping("/status/{trackingId}")
    public String getTransactionStatus(@PathVariable String trackingId) {
        try {
            String token = getAuthToken();
            RestTemplate restTemplate = new RestTemplate();
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(token);

            HttpEntity<Void> entity = new HttpEntity<>(headers);
            @SuppressWarnings("rawtypes")
            ResponseEntity<Map> response = restTemplate.exchange(
                    BASE_URL + "/api/Transactions/GetTransactionStatus?orderTrackingId=" + trackingId,
                    HttpMethod.GET,
                    entity,
                    Map.class
            );

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Integer code = (Integer) response.getBody().get("status_code");
                return (code != null && code == 1) ? "COMPLETED" : (code != null && code == 2 ? "FAILED" : "PENDING");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return "PENDING";
    }
}
