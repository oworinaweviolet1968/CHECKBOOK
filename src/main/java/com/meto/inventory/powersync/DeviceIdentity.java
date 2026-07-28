package com.meto.inventory.powersync;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.UUID;

public class DeviceIdentity {
    private static String cachedDeviceId = null;

    public static synchronized String getDeviceId() {
        if (cachedDeviceId != null) {
            return cachedDeviceId;
        }

        String userHome = System.getProperty("user.home");
        String appData = System.getenv("APPDATA");
        String rootDir = (appData != null) ? appData : userHome;
        File dir = new File(rootDir, "METO_IMS_DATA");
        if (!dir.exists()) {
            dir.mkdirs();
        }

        File idFile = new File(dir, "device_identity.id");
        if (idFile.exists()) {
            try {
                String idStr = Files.readString(idFile.toPath()).trim();
                if (!idStr.isEmpty()) {
                    cachedDeviceId = idStr;
                    return cachedDeviceId;
                }
            } catch (IOException ignored) {}
        }

        String newId = UUID.randomUUID().toString();
        try {
            Files.writeString(idFile.toPath(), newId);
            cachedDeviceId = newId;
        } catch (IOException e) {
            cachedDeviceId = newId; // Fallback to memory instance
        }
        return cachedDeviceId;
    }
}
