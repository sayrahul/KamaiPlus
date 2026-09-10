package com.kamaiplus.pos;

import android.app.Notification;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class PaymentNotificationListener extends NotificationListenerService {
    private static final String TAG = "PaymentNotification";

    public interface PaymentCallback {
        void onPaymentDetected(long amountPaise, String appName, String sender, String rawText);
    }

    private static PaymentCallback activeCallback = null;

    public static void setCallback(PaymentCallback callback) {
        activeCallback = callback;
    }

    // RegEx patterns for extracting Indian currency amounts
    // Matches: ₹170, ₹ 170.50, Rs. 170, Rs 1,450.00, INR 500, etc.
    private static final Pattern AMOUNT_PATTERN = Pattern.compile(
            "(?:₹|Rs\\.?|INR)\\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)",
            Pattern.CASE_INSENSITIVE
    );

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        if (sbn == null || sbn.getNotification() == null) return;

        String pkg = sbn.getPackageName();
        Bundle extras = sbn.getNotification().extras;
        if (extras == null) return;

        CharSequence titleSeq = extras.getCharSequence(Notification.EXTRA_TITLE);
        CharSequence textSeq = extras.getCharSequence(Notification.EXTRA_TEXT);
        CharSequence bigTextSeq = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);

        String title = titleSeq != null ? titleSeq.toString() : "";
        String text = textSeq != null ? textSeq.toString() : "";
        if (bigTextSeq != null && bigTextSeq.length() > text.length()) {
            text = bigTextSeq.toString();
        }

        String combined = (title + " " + text).toLowerCase();

        // 1. Identify source app
        String appName = identifyApp(pkg, combined);
        if (appName == null) {
            // Check if it's an SMS app receiving bank credit SMS
            if (isBankCreditMessage(combined)) {
                appName = "Bank SMS";
            } else {
                return;
            }
        }

        // 2. Reject debit or sent notifications
        if (isDebitMessage(combined)) {
            Log.d(TAG, "Ignored debit notification: " + text);
            return;
        }

        // 3. Extract Amount
        long amountPaise = extractAmountPaise(text.isEmpty() ? title : text);
        if (amountPaise <= 0 && !text.isEmpty()) {
            amountPaise = extractAmountPaise(title);
        }

        if (amountPaise > 0) {
            Log.i(TAG, "✓ Payment Detected: " + amountPaise + " paise via " + appName);
            if (activeCallback != null) {
                final long finalAmount = amountPaise;
                final String finalApp = appName;
                final String finalTitle = title;
                final String finalText = text;
                activeCallback.onPaymentDetected(finalAmount, finalApp, finalTitle, finalText);
            }
        }
    }

    private String identifyApp(String pkg, String content) {
        if (pkg == null) return null;

        if (pkg.contains("com.phonepe.app")) return "PhonePe";
        if (pkg.contains("net.one97.paytm") || pkg.contains("com.paytm.business")) return "Paytm";
        if (pkg.contains("com.google.android.apps.nbu.paisa.user")) return "Google Pay";
        if (pkg.contains("in.org.npci.upiapp")) return "BHIM UPI";
        if (pkg.contains("com.bharatpe.app")) return "BharatPe";
        if (pkg.contains("com.whatsapp")) {
            if (content.contains("payment") || content.contains("received") || content.contains("₹") || content.contains("rs")) {
                return "WhatsApp Pay";
            }
        }

        return null;
    }

    private boolean isDebitMessage(String text) {
        // Discard messages indicating money went OUT of the account
        return (text.contains("debited") ||
                text.contains("withdrawn") ||
                text.contains("paid to") ||
                text.contains("spent") ||
                text.contains("sent to") ||
                text.contains("transferred to")) &&
                !text.contains("credited") &&
                !text.contains("received");
    }

    private boolean isBankCreditMessage(String text) {
        boolean hasCredit = text.contains("credited") ||
                text.contains("received") ||
                text.contains("deposited") ||
                text.contains("prapt hue") ||
                text.contains("jama");

        boolean hasBankRef = text.contains("upi") ||
                text.contains("a/c") ||
                text.contains("acct") ||
                text.contains("bank") ||
                text.contains("inr") ||
                text.contains("₹") ||
                text.contains("rs.");

        return hasCredit && hasBankRef;
    }

    private long extractAmountPaise(String raw) {
        if (raw == null || raw.isEmpty()) return 0;

        Matcher matcher = AMOUNT_PATTERN.matcher(raw);
        if (matcher.find()) {
            try {
                String amtStr = matcher.group(1).replace(",", "").trim();
                double amtDouble = Double.parseDouble(amtStr);
                return Math.round(amtDouble * 100);
            } catch (Exception e) {
                Log.e(TAG, "Failed to parse amount from: " + raw, e);
            }
        }
        return 0;
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        // Not needed for payment receipt detection
    }
}
