const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { FieldValue } = require("firebase-admin/firestore");

initializeApp();

/**
 * Triggered automatically when an Admin dispatches a push notification from the Admin Console.
 * Sends a real FCM System Tray push notification with high priority, sound & vibration to all merchants.
 */
exports.onAdminPushCreated = onDocumentCreated(
  "admin_push_notifications/{notificationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const data = snap.data();
    if (!data) return null;

    const title = data.title || "KamaiPlus POS Alert";
    const body = data.body || "";
    const actionUrl = data.action_url || "";
    const targetAudience = data.target_audience || "all";

    console.log(`[FCM] Processing notification: "${title}" for audience: ${targetAudience}`);

    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        actionUrl: actionUrl,
        type: "admin_broadcast",
        notificationId: event.params.notificationId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "kamai_pos_channel",
          sound: "default",
          priority: "high",
          defaultVibrateTimings: true,
          defaultSound: true,
          visibility: "public",
          icon: "ic_launcher",
        },
      },
      topic: "all_merchants",
    };

    try {
      const response = await getMessaging().send(payload);
      console.log(`[FCM] Successfully dispatched to topic all_merchants: ${response}`);

      await snap.ref.update({
        status: "delivered",
        fcm_message_id: response,
        delivered_at: FieldValue.serverTimestamp(),
      });
      return response;
    } catch (error) {
      console.error("[FCM] Failed to dispatch push notification:", error);
      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
      return null;
    }
  }
);
