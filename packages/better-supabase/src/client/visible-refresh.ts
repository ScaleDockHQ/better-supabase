/** The part of a browser auth client `refreshOnVisible` calls. */
export interface VisibleRefreshClient {
  readonly auth: {
    getSession(): Promise<{
      data: { session: { expires_at?: number } | null };
    }>;
    refreshSession(): Promise<unknown>;
  };
}

interface VisibleDocument {
  readonly visibilityState: string;
  addEventListener(type: "visibilitychange", listener: () => void): void;
  removeEventListener(type: "visibilitychange", listener: () => void): void;
}

function browserDocument(): VisibleDocument | undefined {
  // SAFETY: `document` exists in a browser and is absent in Node. Only the
  // visibility listener fields are read.
  const scope = globalThis as { document?: VisibleDocument };
  const doc = scope.document;

  if (doc === undefined || typeof doc.addEventListener !== "function") {
    return undefined;
  }

  return doc;
}

/**
 * Refreshes the session when a hidden tab becomes visible and the access token
 * is inside `leewaySeconds` of expiry. Background tabs throttle the auth-js
 * timer, so the refresh otherwise waits until the next interval. Returns the
 * function that removes the listener. No-op without `document`.
 */
export function refreshOnVisible(
  client: VisibleRefreshClient,
  leewaySeconds = 60,
): () => void {
  const doc = browserDocument();

  if (!doc) {
    return () => undefined;
  }

  const onVisible = (): void => {
    if (doc.visibilityState === "hidden") {
      return;
    }

    void client.auth.getSession().then(({ data }) => {
      const expiresAt = data.session?.expires_at;

      if (expiresAt === undefined) {
        return;
      }

      const now = Math.floor(Date.now() / 1000);

      if (expiresAt - leewaySeconds <= now) {
        void client.auth.refreshSession();
      }
    });
  };

  doc.addEventListener("visibilitychange", onVisible);

  return () => {
    doc.removeEventListener("visibilitychange", onVisible);
  };
}
