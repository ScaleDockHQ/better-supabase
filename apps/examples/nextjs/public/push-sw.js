// Shows the web pushes a sender delivers to the subscriptions the push
// opt-in card registers. The payload is the JSON a Web Push sender writes:
// { title, body, actionPath }.
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};

  event.waitUntil(
    self.registration.showNotification(data.title ?? "New notification", {
      body: data.body,
      data: { actionPath: data.actionPath ?? "/" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow(event.notification.data.actionPath));
});
