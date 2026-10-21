import {
  createPush,
  registerDevice,
  rpcTransport,
} from "better-supabase/blocks/push";
import * as Notifications from "expo-notifications";
import { useEffect } from "react";
import { Platform } from "react-native";

import { supabase } from "@/lib/supabase/client.native";

const devices = createPush({
  transport: rpcTransport(supabase, { schema: "api" }),
});

/**
 * Registers this device's Expo push token for the signed-in user. Call it once
 * inside the signed-in part of the app.
 */
export function usePushRegistration(): void {
  useEffect(() => {
    void registerDevice({
      notifications: Notifications,
      devices,
      platform: Platform.OS,
      projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
    });
  }, []);
}
