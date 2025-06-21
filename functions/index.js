// The Cloud Functions for Firebase SDK to create Cloud Functions and set up triggers.
const functions = require("firebase-functions");
// The Firebase Admin SDK to access the Firebase Realtime Database.
const admin = require("firebase-admin");

// *** MODIFIED: Import the specific database function needed from the v2 SDK ***
const { onValueCreated } = require("firebase-functions/v2/database");

admin.initializeApp();

/**
 * This function triggers whenever a new notification is created in the
 * Realtime Database at /notifications/{userId}/{notificationId}.
 * It uses the modern (v2) syntax.
 */
exports.sendPushNotification = onValueCreated("/notifications/{userId}/{notificationId}", async (event) => {
    // Get the notification data that was just created.
    const snapshot = event.data;
    const notificationData = snapshot.val();
    const userId = event.params.userId;
    const notificationId = event.params.notificationId;

    console.log(`New notification for user: ${userId}`, notificationData);

    // --- Don't send a notification if it has already been read ---
    if (notificationData.isRead) {
        return console.log(`Notification ${notificationId} is already read. Aborting.`);
    }

    // --- Get the recipient's FCM push token ---
    const userTokenSnapshot = await admin.database()
      .ref(`/users/${userId}/fcmToken`).get();

    if (!userTokenSnapshot.exists()) {
      return console.log(`User ${userId} has no FCM token. Cannot send notification.`);
    }
    const fcmToken = userTokenSnapshot.val();
    console.log(`FCM Token found: ${fcmToken}`);

    // --- Construct the notification message payload for FCM ---
    const payload = {
      notification: {
        title: notificationData.title,
        body: notificationData.body,
      },
      token: fcmToken,
      data: {
        bookingId: notificationData.bookingId || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK", // Important for some versions of Flutter
      },
      apns: {
        payload: {
            aps: {
                sound: "default",
            },
        },
      },
      android: {
        notification: {
            sound: "default",
        },
      },
    };

    // --- Send the notification using the FCM Admin SDK ---
    try {
      console.log("Sending FCM payload:", payload);
      const response = await admin.messaging().send(payload);
      console.log("Successfully sent message:", response);
      return response;
    } catch (error) {
      console.error("Error sending message:", error);
      return null;
    }
  });
