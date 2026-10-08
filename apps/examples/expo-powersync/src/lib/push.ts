import {
  createPushDevices,
  registerDevice,
  rpcTransport,
  unregisterOnSignOut,
} from "better-supabase/blocks/push";
import * as Notifications from "expo-notifications";
import { useEffect } from "react";
import { Platform } from "react-native";

import { supabase } from "./supabase/native";

const devices = createPushDevices({
  transport: rpcTransport(supabase, { schema: "api" }),
});

let token: string | undefined;

/** Registers this device's Expo push token for the signed-in user. */
export function usePushRegistration(): void {
  useEffect(() => {
    void registerDevice({
      notifications: Notifications,
      devices,
      platform: Platform.OS,
      projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
    }).then((result) => {
      if (result.ok && result.data) token = result.data.token;
    });
  }, []);
}

/** Removes this device's token while the session can still do it, then signs out. */
export const signOut = unregisterOnSignOut({
  signOut: () => supabase.auth.signOut(),
  devices,
  token: () => token,
});
