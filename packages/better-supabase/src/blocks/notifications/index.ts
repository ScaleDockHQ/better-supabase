export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export type {
  NotificationChannel,
  NotificationMessage,
  NotificationSendResult,
} from "./channel.ts";

export { createNotifications } from "./notifications.ts";

export { mailHeaders } from "./delivery.ts";

export type {
  DeliveryChannel,
  DeliveryMessages,
  DeliveryReceipt,
  DeliverySendOptions,
  DeliveryTransport,
  EmailMessage,
  MailCategory,
  UnsubscribeTarget,
} from "./delivery.ts";

export { emailChannel } from "./email.ts";

export type { ComposedEmail, EmailChannelOptions } from "./email.ts";

export {
  ResendError,
  resendTransport,
  type ResendTransportOptions,
} from "./transports/resend.ts";

export {
  resendDeliveryEvent,
  resendSuppressions,
  resendWebhook,
  type ResendWebhookOptions,
  type SuppressionWriter,
} from "./transports/resend-webhook.ts";

export {
  watcherHandler,
  watcherSink,
  type WatchedEventData,
  type WatchedOutboxEvent,
  type WatcherRule,
  type WatcherSinkOptions,
} from "./watcher-sink.ts";

export type {
  AvatarUrls,
  DeliverOptions,
  DeliverResult,
  DeliveryEvent,
  DeliveryEventInput,
  DeliveryEventKind,
  ListOptions,
  NotificationActor,
  NotificationCounts,
  NotificationOf,
  NotificationPage,
  NotificationPreference,
  NotificationSinkOptions,
  NotificationSubscription,
  NotificationSuppression,
  NotificationTypes,
  NotificationUpdate,
  Notifications,
  NotificationsOptions,
  PageOptions,
  RecordedDeliveryEvent,
  Rendered,
  SendInput,
  SentNotification,
  SinkNotification,
  SubjectDelivery,
  SubscriptionLevel,
  SuppressInput,
  SuppressionReason,
} from "./api-types.ts";

export type {
  NotificationItem,
  NotificationSubject,
  RenderedText,
} from "./types.ts";

export { createNotificationsController, unreadCount } from "./client.ts";

export type {
  NotificationFeedOptions,
  NotificationsActions,
  NotificationsController,
  NotificationsControllerOptions,
  NotificationSource,
  NotificationsSnapshot,
} from "./client.ts";

export { notificationsBlock } from "./manifest.ts";

export { notificationsEvents } from "./events.ts";

export type { NotificationsEvents } from "./events.ts";
