import type {
  ClientPorts,
  DeepLinkPort,
  FilePickerPort,
  KeyboardPort,
  PickedFile,
  PushTokenPort,
  StoragePort,
} from "./ports.ts";

// `better-supabase/client` also loads in apps without the DOM lib (an Edge
// Function calling `functions`), so these ports type only the members of
// the browser globals they use and look the globals up at call time.

interface Listenable {
  addEventListener(type: string, listener: (event: unknown) => void): void;
  removeEventListener(type: string, listener: (event: unknown) => void): void;
}

interface KeyEventLike {
  readonly key: string;
  readonly metaKey: boolean;
  readonly ctrlKey: boolean;
  readonly shiftKey: boolean;
  readonly altKey: boolean;
  preventDefault(): void;
}

interface WindowLike extends Listenable {
  readonly location: { readonly href: string };
}

interface StringStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

interface FileLike extends Blob {
  readonly name: string;
}

interface FileInputLike extends Listenable {
  type: string;
  multiple: boolean;
  accept: string;
  readonly files: Iterable<FileLike> | null;
  click(): void;
}

interface DocumentLike {
  createElement(tag: "input"): FileInputLike;
}

/** The part of a `ServiceWorkerRegistration` the push token port uses. */
export interface PushRegistrationLike {
  readonly pushManager: {
    getSubscription(): Promise<unknown>;
    subscribe(options: {
      readonly userVisibleOnly: boolean;
      readonly applicationServerKey: Uint8Array<ArrayBuffer>;
    }): Promise<unknown>;
  };
}

interface NotificationLike {
  readonly permission: string;
  requestPermission(): Promise<string>;
}

interface NavigatorLike {
  /** Present on every runtime's `navigator`, so Node's fits too. */
  readonly userAgent?: string;
  readonly serviceWorker?: { readonly ready: Promise<PushRegistrationLike> };
}

function keyEvent(event: unknown): KeyEventLike | undefined {
  if (
    typeof event !== "object" ||
    event === null ||
    !("key" in event) ||
    typeof event.key !== "string"
  ) {
    return undefined;
  }

  // SAFETY: an event with a string `key` is a KeyboardEvent, which carries the modifier flags and preventDefault.
  return event as KeyEventLike;
}

/** The browser globals the ports read; each is missing outside a browser. */
interface BrowserGlobals {
  readonly globalThis: unknown;
  readonly window?: WindowLike;
  readonly document?: DocumentLike;
  readonly navigator?: NavigatorLike;
  readonly Notification?: NotificationLike;
  readonly localStorage?: StringStore;
  readonly sessionStorage?: StringStore;
}

const browser = (): BrowserGlobals => globalThis;

/** Reading `localStorage` throws where the browser blocks it. */
function storageOf(kind: "local" | "session"): StringStore | undefined {
  return kind === "local" ? browser().localStorage : browser().sessionStorage;
}

/**
 * The storage port over `localStorage` (or `sessionStorage`). Reads resolve
 * with `null` and writes do nothing where storage is missing or blocked.
 */
export function webStorage(kind: "local" | "session" = "local"): StoragePort {
  const run = <T>(
    apply: (storage: StringStore) => T,
    fallback: T,
  ): Promise<T> => {
    try {
      const storage = storageOf(kind);

      return Promise.resolve(storage ? apply(storage) : fallback);
    } catch {
      return Promise.resolve(fallback);
    }
  };

  return {
    get: (key) => run((storage) => storage.getItem(key), null),
    set: (key, value) =>
      run((storage) => {
        storage.setItem(key, value);
      }, undefined),
    remove: (key) =>
      run((storage) => {
        storage.removeItem(key);
      }, undefined),
  };
}

/** The keyboard port over `keydown` on `window`; `mod` matches Cmd and Ctrl. */
export function webKeyboard(): KeyboardPort {
  return (shortcut, run) => {
    const target = browser().window;

    if (!target) {
      return () => undefined;
    }

    const onKey = (raw: unknown): void => {
      const event = keyEvent(raw);

      if (
        event === undefined ||
        event.key.toLowerCase() !== shortcut.key.toLowerCase() ||
        (event.metaKey || event.ctrlKey) !== (shortcut.mod ?? false) ||
        event.shiftKey !== (shortcut.shift ?? false) ||
        event.altKey !== (shortcut.alt ?? false)
      ) {
        return;
      }

      event.preventDefault();
      run();
    };

    target.addEventListener("keydown", onKey);

    return () => {
      target.removeEventListener("keydown", onKey);
    };
  };
}

function pickedFile(file: FileLike): PickedFile {
  return {
    name: file.name,
    type: file.type === "" ? undefined : file.type,
    size: file.size,
    uri: undefined,
    read: () => Promise.resolve(file),
  };
}

/** The file picker port over a hidden `<input type="file">`. */
export function webFilePicker(): FilePickerPort {
  return (options = {}) =>
    new Promise((resolve) => {
      const page = browser().document;

      if (!page) {
        resolve([]);

        return;
      }

      const input = page.createElement("input");
      input.type = "file";
      input.multiple = options.multiple ?? false;

      if (options.accept) {
        input.accept = options.accept.join(",");
      }

      input.addEventListener("change", () => {
        resolve([...(input.files ?? [])].map(pickedFile));
      });
      input.addEventListener("cancel", () => {
        resolve([]);
      });
      input.click();
    });
}

/** The deep link port over `location`, `popstate` and `hashchange`. */
export function webDeepLinks(): DeepLinkPort {
  return {
    initial: () => Promise.resolve(browser().window?.location.href ?? null),
    subscribe: (listener) => {
      const target = browser().window;

      if (!target) {
        return () => undefined;
      }

      const onChange = (): void => {
        listener(target.location.href);
      };

      target.addEventListener("popstate", onChange);
      target.addEventListener("hashchange", onChange);

      return () => {
        target.removeEventListener("popstate", onChange);
        target.removeEventListener("hashchange", onChange);
      };
    },
  };
}

export interface WebPushTokenOptions {
  /** The VAPID public key, base64url-encoded. */
  readonly vapidPublicKey: string;
  /**
   * The service worker that receives the pushes. Default
   * `navigator.serviceWorker.ready`.
   */
  readonly registration?: () => Promise<PushRegistrationLike>;
}

function keyBytes(base64url: string): Uint8Array<ArrayBuffer> {
  const base64 = base64url.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);

  return Uint8Array.from(atob(padded), (char) => char.codePointAt(0) ?? 0);
}

/**
 * The push token port over the Push API: the token is the JSON of the browser's
 * push subscription, which a Web Push sender needs.
 */
export function webPushToken(options: WebPushTokenOptions): PushTokenPort {
  return {
    provider: "webpush",
    token: async ({ request = true } = {}) => {
      const notification = browser().Notification;
      const worker = browser().navigator?.serviceWorker;

      if (!notification || !worker) {
        return null;
      }

      let permission = notification.permission;

      if (permission === "default" && request) {
        permission = await notification.requestPermission();
      }

      if (permission !== "granted") {
        return null;
      }

      const registration = await (options.registration?.() ?? worker.ready);

      const subscription =
        (await registration.pushManager.getSubscription()) ??
        (await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: keyBytes(options.vapidPublicKey),
        }));

      return JSON.stringify(subscription);
    },
  };
}

/**
 * The web ports `createClient` uses: storage, the keyboard, the file picker and
 * deep links.
 */
export function webPorts(): ClientPorts {
  return {
    storage: webStorage(),
    keyboard: webKeyboard(),
    files: webFilePicker(),
    links: webDeepLinks(),
  };
}
