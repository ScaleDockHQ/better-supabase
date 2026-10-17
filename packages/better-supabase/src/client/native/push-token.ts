import type { PushTokenPort } from "../ports.ts";

/** The part of `expo-notifications` the push token port uses. */
export interface ExpoNotificationsLike {
  getPermissionsAsync(): Promise<{ readonly status: string }>;
  requestPermissionsAsync(): Promise<{ readonly status: string }>;
  getExpoPushTokenAsync(options?: {
    readonly projectId?: string;
  }): Promise<{ readonly data: string }>;
}

export interface ExpoPushTokenOptions {
  /** `Constants.easConfig?.projectId`; Expo needs it outside Expo Go. */
  readonly projectId?: string | undefined;
}

/** The push token port over `expo-notifications`: the Expo push token. */
export function expoPushToken(
  notifications: ExpoNotificationsLike,
  options: ExpoPushTokenOptions = {},
): PushTokenPort {
  return {
    provider: "expo",
    token: async ({ request = true } = {}) => {
      let { status } = await notifications.getPermissionsAsync();

      if (status !== "granted" && request) {
        ({ status } = await notifications.requestPermissionsAsync());
      }

      if (status !== "granted") {
        return null;
      }

      const { data } = await notifications.getExpoPushTokenAsync(
        options.projectId === undefined ? {} : { projectId: options.projectId },
      );

      return data;
    },
  };
}
