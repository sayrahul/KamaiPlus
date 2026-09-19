package com.kamaiplus.pos;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.ContentValues;
import android.content.ClipData;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintManager;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.database.Cursor;
import android.speech.tts.TextToSpeech;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.text.TextUtils;
import android.text.TextPaint;
import androidx.activity.EdgeToEdge;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.content.FileProvider;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public class MainActivity extends FlutterFragmentActivity implements TextToSpeech.OnInitListener {
    private static final String SOUNDBOX_CHANNEL = "com.kamaiplus.pos/soundbox";
    private static final String BT_CHANNEL = "com.kamaiplus.pos/bluetooth_printer";
    private static final String NOTIFICATION_CHANNEL = "com.kamaiplus.pos/notifications";
    private static final String PDF_CHANNEL = "com.kamaiplus.pos/pdf_engine";
    private static final String APP_CONTROL_CHANNEL = "com.kamaiplus.pos/app_control";
    private static final String CONTACTS_CHANNEL = "com.kamaiplus.pos/contacts";
    private static final String SHORTCUT_CHANNEL = "com.kamaiplus.pos/shortcuts";
    private static final String SHARE_CHANNEL = "com.kamaiplus.pos/share_target";
    private static final String PAYMENT_DETECTOR_CHANNEL = "com.kamaiplus.pos/payment_detector";
    private static final String CHANNEL_ID = "kamai_pos_channel";
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
    private static final int REQUEST_CODE_PICK_CONTACT = 5001;

    private TextToSpeech tts;
    private boolean isTtsReady = false;
    // Counter-scanner beep for rapid barcode billing (scan_feedback_service.dart).
    private ToneGenerator scanTone;
    private String pendingSpeakText = null;
    private String pendingSpeakLang = null;
    private MethodChannel.Result pendingContactResult;
    private String pendingShortcut = null;
    private String pendingSharedFile = null;
    private MethodChannel shortcutMethodChannel;
    private MethodChannel shareMethodChannel;
    private MethodChannel paymentDetectorChannel;

    // =========================================================================
    // BITMAP DOWNSAMPLING HELPERS (PLAY CONSOLE MEMORY / inSampleSize COMPLIANCE)
    // =========================================================================
    private static int calculateInSampleSize(BitmapFactory.Options options, int reqWidth, int reqHeight) {
        final int height = options.outHeight;
        final int width = options.outWidth;
        int inSampleSize = 1;

        if (height > reqHeight || width > reqWidth) {
            final int halfHeight = height / 2;
            final int halfWidth = width / 2;
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2;
            }
        }
        return Math.max(1, inSampleSize);
    }

    private static Bitmap decodeSampledBitmapFromFile(String filePath, int reqWidth, int reqHeight) {
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(filePath, options);
            if (options.outWidth <= 0 || options.outHeight <= 0) return null;

            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight);
            options.inJustDecodeBounds = false;
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeFile(filePath, options);
        } catch (Throwable t) {
            return null;
        }
    }

    private static Bitmap decodeSampledBitmapFromByteArray(byte[] data, int reqWidth, int reqHeight) {
        try {
            if (data == null || data.length == 0) return null;
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(data, 0, data.length, options);
            if (options.outWidth <= 0 || options.outHeight <= 0) return null;

            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight);
            options.inJustDecodeBounds = false;
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeByteArray(data, 0, data.length, options);
        } catch (Throwable t) {
            return null;
        }
    }

    private Bitmap decodeSampledBitmapFromResource(int resId, int reqWidth, int reqHeight) {
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeResource(getResources(), resId, options);
            if (options.outWidth <= 0 || options.outHeight <= 0) return null;

            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight);
            options.inJustDecodeBounds = false;
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeResource(getResources(), resId, options);
        } catch (Throwable t) {
            return null;
        }
    }

    private static String safeEllipsize(String text, Paint paint, float maxPixelWidth) {
        if (text == null || text.isEmpty()) return "";
        try {
            CharSequence ellipsized = TextUtils.ellipsize(text, new TextPaint(paint), maxPixelWidth, TextUtils.TruncateAt.END);
            return ellipsized.toString();
        } catch (Throwable ignored) {
            return text;
        }
    }

    private static void drawRightAlignedText(Canvas canvas, String text, float rightX, float y, Paint paint) {
        if (text == null || text.isEmpty()) return;
        float width = paint.measureText(text);
        canvas.drawText(text, rightX - width, y, paint);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
    }

    @Override
    protected void onResume() {
        super.onResume();
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    private void handleIntent(android.content.Intent intent) {
        if (intent == null) return;

        // 1. Check legacy test_screen extra
        if (intent.hasExtra("test_screen")) {
            String testScreen = intent.getStringExtra("test_screen");
            android.content.SharedPreferences sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            sp.edit().putString("flutter.test_screen", testScreen).commit();
        }

        // 2. Check Shortcut from extras or deep link
        String shortcutTarget = null;
        if (intent.hasExtra("shortcut")) {
            shortcutTarget = intent.getStringExtra("shortcut");
        } else if (intent.getData() != null) {
            Uri data = intent.getData();
            if ("kamaiplus".equalsIgnoreCase(data.getScheme())) {
                if ("shortcut".equalsIgnoreCase(data.getHost()) || (data.getPath() != null && data.getPath().contains("shortcut"))) {
                    shortcutTarget = data.getLastPathSegment();
                }
            }
        }

        if (shortcutTarget != null && !shortcutTarget.isEmpty()) {
            if (shortcutMethodChannel != null) {
                final String target = shortcutTarget;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        shortcutMethodChannel.invokeMethod("onShortcutReceived", target);
                    }
                });
            } else {
                pendingShortcut = shortcutTarget;
            }
        }

        // 3. Check Share-To Intent (ACTION_SEND with EXTRA_STREAM)
        if (Intent.ACTION_SEND.equals(intent.getAction())) {
            Uri streamUri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (streamUri != null) {
                handleSharedStream(streamUri, intent.getType());
            }
        }
    }

    private void handleSharedStream(Uri uri, String mimeType) {
        try {
            File cacheDir = new File(getCacheDir(), "shared_bills");
            if (!cacheDir.exists()) cacheDir.mkdirs();
            String ext = (mimeType != null && mimeType.contains("pdf")) ? ".pdf" : ".jpg";
            File dest = new File(cacheDir, "shared_bill_" + System.currentTimeMillis() + ext);
            try (InputStream in = getContentResolver().openInputStream(uri);
                 FileOutputStream out = new FileOutputStream(dest)) {
                if (in != null) {
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = in.read(buffer)) != -1) {
                        out.write(buffer, 0, len);
                    }
                    final String path = dest.getAbsolutePath();
                    if (shareMethodChannel != null) {
                        runOnUiThread(new Runnable() {
                            @Override
                            public void run() {
                                shareMethodChannel.invokeMethod("onFileShared", path);
                            }
                        });
                    } else {
                        pendingSharedFile = path;
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_CODE_PICK_CONTACT) {
            if (pendingContactResult != null) {
                if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                    Uri contactUri = data.getData();
                    String[] projection = new String[]{
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER
                    };
                    try (Cursor cursor = getContentResolver().query(contactUri, projection, null, null, null)) {
                        if (cursor != null && cursor.moveToFirst()) {
                            int nameIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME);
                            int phoneIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER);
                            String name = nameIdx != -1 ? cursor.getString(nameIdx) : "";
                            String phone = phoneIdx != -1 ? cursor.getString(phoneIdx) : "";
                            Map<String, String> res = new HashMap<>();
                            res.put("name", name != null ? name : "");
                            res.put("phone", phone != null ? phone : "");
                            pendingContactResult.success(res);
                            pendingContactResult = null;
                            return;
                        }
                    } catch (Exception e) {
                        pendingContactResult.error("CONTACT_QUERY_ERROR", e.getMessage(), null);
                        pendingContactResult = null;
                        return;
                    }
                }
                pendingContactResult.success(null);
                pendingContactResult = null;
            }
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            CharSequence name = "KamaiPlus Billing & Invoices";
            String description = "Notifications for sales, invoices, PDF downloads and sync";
            int importance = NotificationManager.IMPORTANCE_HIGH;
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, name, importance);
            channel.setDescription(description);
            channel.enableVibration(true);
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        createNotificationChannel();

        // App Control Engine (Minimize to background without destroying counter state)
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), APP_CONTROL_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("moveTaskToBack".equals(call.method)) {
                            moveTaskToBack(true);
                            result.success(true);
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // Contacts Picker Channel (Zero-Permission Native Phonebook Selection)
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CONTACTS_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("pickContact".equals(call.method)) {
                            pendingContactResult = result;
                            Intent pickIntent = new Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI);
                            startActivityForResult(pickIntent, REQUEST_CODE_PICK_CONTACT);
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // App Shortcuts Channel (Launcher Icon Long-Press & Widgets)
        shortcutMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHORTCUT_CHANNEL);
        shortcutMethodChannel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
            @Override
            public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                if ("getInitialShortcut".equals(call.method)) {
                    String s = pendingShortcut;
                    pendingShortcut = null;
                    result.success(s);
                } else {
                    result.notImplemented();
                }
            }
        });

        // Share Target Channel ("Send to KamaiPlus" from WhatsApp / Gallery)
        shareMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHARE_CHANNEL);
        shareMethodChannel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
            @Override
            public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                if ("getInitialSharedFile".equals(call.method)) {
                    String f = pendingSharedFile;
                    pendingSharedFile = null;
                    result.success(f);
                } else {
                    result.notImplemented();
                }
            }
        });

        // Native UPI Payment Detection Channel (Zero-Cost Soundbox & In-App Notification Detector)
        paymentDetectorChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PAYMENT_DETECTOR_CHANNEL);
        paymentDetectorChannel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
            @Override
            public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                switch (call.method) {
                    case "isNotificationAccessGranted": {
                        boolean granted = false;
                        String pkgName = getPackageName();
                        String flat = android.provider.Settings.Secure.getString(getContentResolver(), "enabled_notification_listeners");
                        if (flat != null && !flat.isEmpty()) {
                            String[] names = flat.split(":");
                            for (String name : names) {
                                android.content.ComponentName cn = android.content.ComponentName.unflattenFromString(name);
                                if (cn != null && pkgName.equals(cn.getPackageName())) {
                                    granted = true;
                                    break;
                                }
                            }
                        }
                        result.success(granted);
                        break;
                    }
                    case "openNotificationAccessSettings": {
                        try {
                            Intent intent = new Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS);
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(intent);
                            result.success(true);
                        } catch (Exception e) {
                            result.error("SETTINGS_ERROR", e.getMessage(), null);
                        }
                        break;
                    }
                    case "simulatePayment": {
                        Number amt = call.argument("amountPaise");
                        long amountPaise = amt != null ? amt.longValue() : 0;
                        String appName = call.argument("appName") != null ? call.argument("appName").toString() : "PhonePe";
                        forwardPaymentToFlutter(amountPaise, appName, "Customer", "Simulated Payment");
                        result.success(true);
                        break;
                    }
                    default:
                        result.notImplemented();
                        break;
                }
            }
        });

        PaymentNotificationListener.setCallback(new PaymentNotificationListener.PaymentCallback() {
            @Override
            public void onPaymentDetected(long amountPaise, String appName, String sender, String rawText) {
                forwardPaymentToFlutter(amountPaise, appName, sender, rawText);
            }
        });

        // 1. TextToSpeech Voice Engine
        tts = new TextToSpeech(this, this);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SOUNDBOX_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("speak".equals(call.method)) {
                            String text = call.argument("text");
                            String language = call.argument("lang");
                            if (text != null && !text.isEmpty()) {
                                if (isTtsReady) {
                                    Locale locale = "hi".equals(language) ? new Locale("hi", "IN") : new Locale("en", "IN");
                                    tts.setLanguage(locale);
                                    tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "KAMAI_TTS");
                                } else {
                                    // Queue speech announcement so first customer sale of day is never missed
                                    pendingSpeakText = text;
                                    pendingSpeakLang = language;
                                }
                                result.success(true);
                            } else {
                                result.success(false);
                            }
                        } else if ("beep".equals(call.method)) {
                            result.success(playScanBeep("error".equals(call.argument("kind"))));
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // 2. Native ESC/POS Bluetooth Thermal Printing Engine
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), BT_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull final MethodChannel.Result result) {
                        if ("getPairedDevices".equals(call.method)) {
                            try {
                                BluetoothAdapter bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
                                if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
                                    result.success(new ArrayList<Map<String, String>>());
                                    return;
                                }
                                Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
                                List<Map<String, String>> deviceList = new ArrayList<>();
                                if (pairedDevices != null) {
                                    for (BluetoothDevice device : pairedDevices) {
                                        Map<String, String> map = new HashMap<>();
                                        map.put("name", device.getName() != null ? device.getName() : "Thermal Printer");
                                        map.put("address", device.getAddress());
                                        deviceList.add(map);
                                    }
                                }
                                result.success(deviceList);
                            } catch (Exception e) {
                                result.success(new ArrayList<Map<String, String>>());
                            }
                        } else if ("printBytes".equals(call.method)) {
                            final String address = call.argument("address");
                            final byte[] bytes = call.argument("bytes");
                            if (address == null || bytes == null) {
                                result.error("INVALID_ARGS", "Missing address or bytes", null);
                                return;
                            }
                            new Thread(new Runnable() {
                                @Override
                                public void run() {
                                    BluetoothSocket socket = null;
                                    try {
                                        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
                                        BluetoothDevice device = adapter.getRemoteDevice(address);
                                        socket = device.createRfcommSocketToServiceRecord(SPP_UUID);
                                        adapter.cancelDiscovery();
                                        socket.connect();
                                        OutputStream outputStream = socket.getOutputStream();
                                        outputStream.write(bytes);
                                        outputStream.flush();
                                        Thread.sleep(400);
                                        socket.close();
                                        runOnUiThread(new Runnable() {
                                            @Override
                                            public void run() {
                                                result.success(true);
                                            }
                                        });
                                    } catch (final Exception e) {
                                        if (socket != null) {
                                            try { socket.close(); } catch (Exception ignored) {}
                                        }
                                        runOnUiThread(new Runnable() {
                                            @Override
                                            public void run() {
                                                result.error("PRINT_FAIL", e.getMessage() != null ? e.getMessage() : "Printer connection failed", null);
                                            }
                                        });
                                    }
                                }
                            }).start();
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // 3. Native Android Status Bar Notifications
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), NOTIFICATION_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("showNotification".equals(call.method)) {
                            try {
                                String title = call.argument("title");
                                String body = call.argument("body");
                                Integer id = call.argument("id");
                                if (id == null) id = (int) System.currentTimeMillis();

                                Intent intent = new Intent(MainActivity.this, MainActivity.class);
                                intent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                                PendingIntent pendingIntent = PendingIntent.getActivity(
                                        MainActivity.this,
                                        id,
                                        intent,
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0
                                );

                                NotificationCompat.Builder builder = new NotificationCompat.Builder(MainActivity.this, CHANNEL_ID)
                                        .setSmallIcon(R.mipmap.ic_launcher)
                                        .setContentTitle(title != null ? title : "KamaiPlus")
                                        .setContentText(body != null ? body : "")
                                        .setStyle(new NotificationCompat.BigTextStyle().bigText(body != null ? body : ""))
                                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                                        .setAutoCancel(true)
                                        .setContentIntent(pendingIntent);

                                NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                                if (manager != null) {
                                    manager.notify(id, builder.build());
                                }
                                result.success(true);
                            } catch (Exception e) {
                                result.error("NOTIF_ERROR", e.getMessage(), null);
                            }
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // 4. Native PDF Generation, Download & Native Sharing Engine
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PDF_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("generateAndSaveInvoicePdf".equals(call.method)) {
                            try {
                                String invoiceNumber = call.argument("invoiceNumber");
                                String storeName = call.argument("storeName");
                                String storePhone = call.argument("storePhone");
                                String storeAddress = call.argument("storeAddress");
                                String gstin = call.argument("gstin");
                                String storeState = call.argument("storeState");
                                String logoPath = call.argument("logoPath");
                                // Store tagline, honouring the "Show Tagline" toggle in Invoice
                                // Themes. That setting was previously saved and read by nothing —
                                // the PDF engine had no tagline argument at all, so the toggle did
                                // nothing whichever way a merchant set it.
                                final String storeTagline = call.argument("storeTagline");
                                String customerName = call.argument("customerName");
                                String customerPhone = call.argument("customerPhone");
                                String customerGstin = call.argument("customerGstin");
                                String placeOfSupply = call.argument("placeOfSupply");
                                String dateStr = call.argument("dateStr");
                                String paymentMode = call.argument("paymentMode");
                                String subtotalAmount = call.argument("subtotalAmount");
                                String taxableSubtotal = call.argument("taxableSubtotal");
                                String discountAmount = call.argument("discountAmount");
                                String taxAmount = call.argument("taxAmount");
                                String totalAmount = call.argument("totalAmount");
                                String amountInWords = call.argument("amountInWords");
                                List<Map<String, Object>> items = call.argument("items");
                                List<Map<String, Object>> taxBreakup = call.argument("taxBreakup");
                                String themeColorHex = call.argument("themeColorHex");
                                String headingText = call.argument("headingText");
                                String termsText = call.argument("termsText");
                                String footerNote = call.argument("footerNote");
                                Boolean showDynamicUpiQr = call.argument("showDynamicUpiQr");
                                String upiId = call.argument("upiId");
                                String doctorName = call.argument("doctorName");
                                String tableNumber = call.argument("tableNumber");
                                Boolean isPro = call.argument("isPro");
                                if (isPro == null) isPro = false;

                                byte[] qrBytes = call.argument("qrBytes");
                                Bitmap qrBmp = null;
                                if (qrBytes != null && qrBytes.length > 0) {
                                    qrBmp = decodeSampledBitmapFromByteArray(qrBytes, 250, 250);
                                }

                                if (invoiceNumber == null) invoiceNumber = "INV-" + System.currentTimeMillis();
                                if (storeName == null || storeName.trim().isEmpty()) storeName = "KamaiPlus Store";
                                if (customerName == null || customerName.trim().isEmpty()) customerName = "Cash Customer";
                                if (dateStr == null) dateStr = "";
                                if (paymentMode == null) paymentMode = "CASH";
                                if (totalAmount == null) totalAmount = "₹0.00";
                                if (subtotalAmount == null) subtotalAmount = totalAmount;
                                if (taxableSubtotal == null) taxableSubtotal = subtotalAmount;
                                if (amountInWords == null) amountInWords = "";
                                if (items == null) items = new ArrayList<>();
                                if (themeColorHex == null || themeColorHex.trim().isEmpty()) themeColorHex = "#0284C7";
                                if (headingText == null || headingText.trim().isEmpty()) headingText = "TAX INVOICE";
                                if (termsText == null || termsText.trim().isEmpty()) termsText = "1. Goods once sold cannot be taken back.\n2. Electronic invoice generated via Kamai+ POS.";
                                if (footerNote == null || footerNote.trim().isEmpty()) footerNote = "Thank you for shopping with us! Visit again.";
                                if (showDynamicUpiQr == null) showDynamicUpiQr = true;
                                if (upiId == null) upiId = "";

                                int themeColor = Color.rgb(2, 132, 199);
                                try {
                                    themeColor = Color.parseColor(themeColorHex);
                                } catch (Exception ignored) {}

                                // Native PDF Fonts Hierarchy & Configuration (Clean Unicode & Indic Shaping)
                                Typeface regularTypeface = Typeface.create("sans-serif", Typeface.NORMAL);
                                Typeface mediumTypeface = Typeface.create("sans-serif-medium", Typeface.NORMAL);
                                Typeface boldTypeface = Typeface.create("sans-serif", Typeface.BOLD);

                                Paint storeNamePaint = new Paint();
                                storeNamePaint.setColor(Color.rgb(15, 23, 42)); // Slate 900
                                storeNamePaint.setTextSize(14.5f);
                                storeNamePaint.setTypeface(boldTypeface);
                                storeNamePaint.setAntiAlias(true);
                                storeNamePaint.setSubpixelText(true);
                                storeNamePaint.setLinearText(true);

                                Paint taglinePaint = new Paint();
                                taglinePaint.setColor(Color.rgb(100, 116, 139)); // Slate 500
                                taglinePaint.setTextSize(8f);
                                taglinePaint.setTypeface(mediumTypeface);
                                taglinePaint.setAntiAlias(true);
                                taglinePaint.setSubpixelText(true);
                                taglinePaint.setLinearText(true);

                                Paint storeMetaPaint = new Paint();
                                storeMetaPaint.setColor(Color.rgb(71, 85, 105)); // Slate 600
                                storeMetaPaint.setTextSize(8f);
                                storeMetaPaint.setTypeface(regularTypeface);
                                storeMetaPaint.setAntiAlias(true);
                                storeMetaPaint.setSubpixelText(true);
                                storeMetaPaint.setLinearText(true);

                                Paint docTitlePaint = new Paint();
                                docTitlePaint.setColor(themeColor);
                                docTitlePaint.setTextSize(9f);
                                docTitlePaint.setTypeface(boldTypeface);
                                docTitlePaint.setAntiAlias(true);
                                docTitlePaint.setSubpixelText(true);
                                docTitlePaint.setLinearText(true);

                                Paint docMetaBoldPaint = new Paint();
                                docMetaBoldPaint.setColor(Color.rgb(15, 23, 42));
                                docMetaBoldPaint.setTextSize(9.5f);
                                docMetaBoldPaint.setTypeface(boldTypeface);
                                docMetaBoldPaint.setAntiAlias(true);
                                docMetaBoldPaint.setSubpixelText(true);
                                docMetaBoldPaint.setLinearText(true);

                                Paint docMetaSubPaint = new Paint();
                                docMetaSubPaint.setColor(Color.rgb(100, 116, 139));
                                docMetaSubPaint.setTextSize(8f);
                                docMetaSubPaint.setTypeface(regularTypeface);
                                docMetaSubPaint.setAntiAlias(true);
                                docMetaSubPaint.setSubpixelText(true);
                                docMetaSubPaint.setLinearText(true);

                                Paint bodyPaint = new Paint();
                                bodyPaint.setColor(Color.rgb(51, 65, 85)); // Slate 700
                                bodyPaint.setTextSize(8.5f);
                                bodyPaint.setTypeface(regularTypeface);
                                bodyPaint.setAntiAlias(true);
                                bodyPaint.setSubpixelText(true);
                                bodyPaint.setLinearText(true);

                                Paint boldTextPaint = new Paint();
                                boldTextPaint.setColor(Color.rgb(15, 23, 42));
                                boldTextPaint.setTextSize(8.5f);
                                boldTextPaint.setTypeface(boldTypeface);
                                boldTextPaint.setAntiAlias(true);
                                boldTextPaint.setSubpixelText(true);
                                boldTextPaint.setLinearText(true);

                                Paint itemNamePaint = new Paint();
                                itemNamePaint.setColor(Color.rgb(15, 23, 42));
                                itemNamePaint.setTextSize(8.5f);
                                itemNamePaint.setTypeface(mediumTypeface);
                                itemNamePaint.setAntiAlias(true);
                                itemNamePaint.setSubpixelText(true);
                                itemNamePaint.setLinearText(true);

                                Paint subPaint = new Paint();
                                subPaint.setColor(Color.rgb(100, 116, 139)); // Slate 500
                                subPaint.setTextSize(8f);
                                subPaint.setTypeface(regularTypeface);
                                subPaint.setAntiAlias(true);
                                subPaint.setSubpixelText(true);
                                subPaint.setLinearText(true);

                                Paint linePaint = new Paint();
                                linePaint.setColor(Color.rgb(226, 232, 240)); // Slate 200
                                linePaint.setStrokeWidth(0.75f);

                                Paint rowLinePaint = new Paint();
                                rowLinePaint.setColor(Color.rgb(241, 245, 249)); // Slate 100
                                rowLinePaint.setStrokeWidth(0.6f);

                                Paint rowAltBgPaint = new Paint();
                                rowAltBgPaint.setColor(Color.rgb(248, 250, 252));

                                Paint thBgPaint = new Paint();
                                thBgPaint.setColor(themeColor);

                                Paint thTextPaint = new Paint();
                                thTextPaint.setColor(Color.WHITE);
                                thTextPaint.setTextSize(8f);
                                thTextPaint.setTypeface(boldTypeface);
                                thTextPaint.setAntiAlias(true);
                                thTextPaint.setSubpixelText(true);
                                thTextPaint.setLinearText(true);

                                Paint cardBgPaint = new Paint();
                                cardBgPaint.setColor(Color.rgb(248, 250, 252));

                                Paint cardBorderPaint = new Paint();
                                cardBorderPaint.setColor(Color.rgb(226, 232, 240));
                                cardBorderPaint.setStyle(Paint.Style.STROKE);
                                cardBorderPaint.setStrokeWidth(0.75f);

                                Paint statusPaidBgPaint = new Paint();
                                statusPaidBgPaint.setColor(Color.rgb(236, 253, 245));

                                Paint statusPaidBorderPaint = new Paint();
                                statusPaidBorderPaint.setColor(Color.rgb(167, 243, 208));
                                statusPaidBorderPaint.setStyle(Paint.Style.STROKE);
                                statusPaidBorderPaint.setStrokeWidth(0.7f);

                                Paint statusPaidTextPaint = new Paint();
                                statusPaidTextPaint.setColor(Color.rgb(5, 150, 105));
                                statusPaidTextPaint.setTextSize(7.5f);
                                statusPaidTextPaint.setTypeface(boldTypeface);
                                statusPaidTextPaint.setAntiAlias(true);

                                Paint statusUnpaidBgPaint = new Paint();
                                statusUnpaidBgPaint.setColor(Color.rgb(254, 243, 199));

                                Paint statusUnpaidBorderPaint = new Paint();
                                statusUnpaidBorderPaint.setColor(Color.rgb(253, 230, 138));
                                statusUnpaidBorderPaint.setStyle(Paint.Style.STROKE);
                                statusUnpaidBorderPaint.setStrokeWidth(0.7f);

                                Paint statusUnpaidTextPaint = new Paint();
                                statusUnpaidTextPaint.setColor(Color.rgb(180, 83, 9));
                                statusUnpaidTextPaint.setTextSize(7.5f);
                                statusUnpaidTextPaint.setTypeface(boldTypeface);
                                statusUnpaidTextPaint.setAntiAlias(true);

                                Paint discountTextPaint = new Paint();
                                discountTextPaint.setColor(Color.rgb(220, 38, 38));
                                discountTextPaint.setTextSize(8.5f);
                                discountTextPaint.setTypeface(mediumTypeface);
                                discountTextPaint.setAntiAlias(true);

                                Paint grandTotalBg = new Paint();
                                grandTotalBg.setColor(themeColor);

                                // Store Logo (Downsampled to prevent high-res camera photo OOM / Google Play memory warning)
                                Bitmap logoBmp = null;
                                if (logoPath != null && !logoPath.trim().isEmpty()) {
                                    File lf = new File(logoPath);
                                    if (lf.exists() && lf.length() > 0) {
                                        logoBmp = decodeSampledBitmapFromFile(logoPath, 200, 200);
                                    }
                                }

                                // App Icon for Kamai+ Footer Branding
                                Bitmap appIconBmp = decodeSampledBitmapFromResource(R.mipmap.ic_launcher, 64, 64);

                                // Multi-page Calculation (Strict space budgeting to prevent collision)
                                List<List<Map<String, Object>>> pagesItems = new ArrayList<>();
                                int totalItems = items.size();

                                if (totalItems <= 14) {
                                    pagesItems.add(new ArrayList<>(items));
                                } else {
                                    int itemIndex = 0;
                                    int p1Count = Math.min(totalItems - itemIndex, 20);
                                    List<Map<String, Object>> p1List = new ArrayList<>();
                                    for (int i = 0; i < p1Count; i++) p1List.add(items.get(itemIndex++));
                                    pagesItems.add(p1List);

                                    while (itemIndex < totalItems) {
                                        int remaining = totalItems - itemIndex;
                                        if (remaining <= 14) {
                                            List<Map<String, Object>> finalP = new ArrayList<>();
                                            while (itemIndex < totalItems) finalP.add(items.get(itemIndex++));
                                            pagesItems.add(finalP);
                                        } else {
                                            int count = Math.min(remaining, 26);
                                            if (remaining - count > 0 && remaining - count <= 3) {
                                                count -= 3;
                                            }
                                            List<Map<String, Object>> nextP = new ArrayList<>();
                                            for (int i = 0; i < count; i++) nextP.add(items.get(itemIndex++));
                                            pagesItems.add(nextP);
                                        }
                                    }
                                }

                                int totalPages = pagesItems.size();
                                PdfDocument document = new PdfDocument();
                                int globalSNo = 1;

                                float leftX = 36f;
                                float rightX = 559f;

                                for (int pageIdx = 1; pageIdx <= totalPages; pageIdx++) {
                                    PdfDocument.PageInfo pageInfo = new PdfDocument.PageInfo.Builder(595, 842, pageIdx).create();
                                    PdfDocument.Page page = document.startPage(pageInfo);
                                    Canvas canvas = page.getCanvas();

                                    // Top Accent Bar
                                    RectF topAccent = new RectF(leftX, 24, rightX, 27.5f);
                                    canvas.drawRoundRect(topAccent, 1.5f, 1.5f, thBgPaint);

                                    float currentY;

                                    if (pageIdx == 1) {
                                        // =========================================================================
                                        // PAGE 1 HEADER (MODERN RETAIL STORE & DOCUMENT IDENTIFIER)
                                        // =========================================================================
                                        float headerTop = 36f;
                                        float textLeft = leftX;
                                        if (logoBmp != null) {
                                            float logoSize = 44f;
                                            RectF logoCard = new RectF(leftX, headerTop, leftX + logoSize, headerTop + logoSize);
                                            canvas.drawRoundRect(logoCard, 6, 6, cardBgPaint);
                                            canvas.drawRoundRect(logoCard, 6, 6, cardBorderPaint);
                                            RectF logoInner = new RectF(leftX + 2, headerTop + 2, leftX + logoSize - 2, headerTop + logoSize - 2);
                                            Paint bmpPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
                                            canvas.drawBitmap(logoBmp, null, logoInner, bmpPaint);
                                            textLeft = leftX + logoSize + 10;
                                        }

                                        canvas.drawText(safeEllipsize(storeName, storeNamePaint, 270), textLeft, headerTop + 13, storeNamePaint);
                                        float storeMetaY = headerTop + 25;
                                        if (storeTagline != null && !storeTagline.trim().isEmpty()) {
                                            canvas.drawText(safeEllipsize(storeTagline, taglinePaint, 250), textLeft, storeMetaY, taglinePaint);
                                            storeMetaY += 10.5f;
                                        }
                                        if (storeAddress != null && !storeAddress.trim().isEmpty()) {
                                            canvas.drawText(safeEllipsize(storeAddress, storeMetaPaint, 250), textLeft, storeMetaY, storeMetaPaint);
                                            storeMetaY += 10.5f;
                                        }
                                        String contactInfo = "";
                                        if (storePhone != null && !storePhone.trim().isEmpty()) contactInfo += "Ph: " + storePhone + "   ";
                                        if (gstin != null && !gstin.trim().isEmpty()) contactInfo += "GSTIN: " + gstin;
                                        if (storeState != null && !storeState.trim().isEmpty()) contactInfo += " (" + storeState + ")";
                                        if (!contactInfo.isEmpty()) {
                                            canvas.drawText(safeEllipsize(contactInfo, storeMetaPaint, 260), textLeft, storeMetaY, storeMetaPaint);
                                            storeMetaY += 10.5f;
                                        }

                                        // Top Right Header Card (Pill badge & Invoice Numbers)
                                        float pillRight = rightX;
                                        float pillWidth = 145f;
                                        float pillLeft = pillRight - pillWidth;
                                        RectF headingPill = new RectF(pillLeft, headerTop, pillRight, headerTop + 19);
                                        Paint pillBg = new Paint();
                                        pillBg.setColor(Color.argb(24, Color.red(themeColor), Color.green(themeColor), Color.blue(themeColor)));
                                        canvas.drawRoundRect(headingPill, 4, 4, pillBg);
                                        Paint pillBorder = new Paint();
                                        pillBorder.setColor(Color.argb(70, Color.red(themeColor), Color.green(themeColor), Color.blue(themeColor)));
                                        pillBorder.setStyle(Paint.Style.STROKE);
                                        pillBorder.setStrokeWidth(0.75f);
                                        canvas.drawRoundRect(headingPill, 4, 4, pillBorder);

                                        float titleW = docTitlePaint.measureText(headingText);
                                        canvas.drawText(headingText, pillRight - 10 - titleW, headerTop + 13.5f, docTitlePaint);

                                        drawRightAlignedText(canvas, "#" + invoiceNumber, rightX, headerTop + 33, docMetaBoldPaint);
                                        drawRightAlignedText(canvas, "Date: " + dateStr, rightX, headerTop + 45, docMetaSubPaint);
                                        if (placeOfSupply != null && !placeOfSupply.trim().isEmpty()) {
                                            drawRightAlignedText(canvas, "POS: " + placeOfSupply, rightX, headerTop + 56, docMetaSubPaint);
                                        }

                                        float headerBottom = Math.max(storeMetaY + 4, headerTop + 62);
                                        canvas.drawLine(leftX, headerBottom, rightX, headerBottom, linePaint);

                                        // =========================================================================
                                        // 2. BILLED TO (BUYER / CUSTOMER B2B & RETAIL CARD)
                                        // =========================================================================
                                        boolean isB2B = customerGstin != null && !customerGstin.trim().isEmpty();
                                        boolean hasTaxBreakup = taxBreakup != null && !taxBreakup.isEmpty();
                                        boolean hasGst = false;
                                        if (taxAmount != null && !taxAmount.trim().isEmpty() && !taxAmount.equals("₹0.00") && !taxAmount.equals("₹0")) {
                                            hasGst = true;
                                        }
                                        boolean showStatutoryGstColumns = isB2B || hasTaxBreakup || hasGst;

                                        float custTop = headerBottom + 7;
                                        float custHeight = isB2B ? 36 : 28;
                                        RectF custRect = new RectF(leftX, custTop, rightX, custTop + custHeight);
                                        canvas.drawRoundRect(custRect, 5, 5, cardBgPaint);
                                        canvas.drawRoundRect(custRect, 5, 5, cardBorderPaint);

                                        // Left accent bar
                                        RectF custAccent = new RectF(leftX, custTop + 3, leftX + 3, custTop + custHeight - 3);
                                        canvas.drawRoundRect(custAccent, 1.5f, 1.5f, thBgPaint);

                                        String cName = (customerName != null && !customerName.trim().isEmpty()) ? customerName : "Cash Customer";
                                        Paint billedLabelPaint = new Paint(subPaint);
                                        billedLabelPaint.setTextSize(7f);
                                        billedLabelPaint.setTypeface(boldTypeface);
                                        canvas.drawText("BILLED TO:", leftX + 10, custTop + 11.5f, billedLabelPaint);
                                        canvas.drawText(safeEllipsize(cName, boldTextPaint, 240), leftX + 62, custTop + 12f, boldTextPaint);

                                        String custDetails = "";
                                        if (customerPhone != null && !customerPhone.trim().isEmpty()) custDetails += "Ph: " + customerPhone + "   ";
                                        if (tableNumber != null && !tableNumber.trim().isEmpty()) custDetails += "Table: " + tableNumber + "   ";
                                        if (doctorName != null && !doctorName.trim().isEmpty()) custDetails += "Dr: " + doctorName;
                                        if (!custDetails.isEmpty()) {
                                            canvas.drawText(safeEllipsize(custDetails.trim(), subPaint, 280), leftX + 10, custTop + 22.5f, subPaint);
                                        }

                                        if (isB2B) {
                                            String b2bStr = "Buyer GSTIN: " + customerGstin;
                                            if (placeOfSupply != null && !placeOfSupply.trim().isEmpty()) b2bStr += "  •  State: " + placeOfSupply;
                                            canvas.drawText(safeEllipsize(b2bStr, subPaint, 280), leftX + 10, custTop + 32f, subPaint);
                                        }

                                        // Payment Status Pill Badge on right
                                        boolean isCredit = paymentMode.equalsIgnoreCase("UDHAR") || paymentMode.equalsIgnoreCase("CREDIT");
                                        String badgeText = isCredit ? "● UNPAID (CREDIT)" : "● PAID (" + paymentMode.toUpperCase(Locale.ENGLISH) + ")";
                                        Paint payTextPaint = new Paint(isCredit ? statusUnpaidTextPaint : statusPaidTextPaint);
                                        float badgeW = payTextPaint.measureText(badgeText) + 14;
                                        float badgeH = 15;
                                        RectF badgeRect = new RectF(rightX - 8 - badgeW, custTop + (custHeight - badgeH) / 2, rightX - 8, custTop + (custHeight + badgeH) / 2);
                                        canvas.drawRoundRect(badgeRect, 3.5f, 3.5f, isCredit ? statusUnpaidBgPaint : statusPaidBgPaint);
                                        canvas.drawRoundRect(badgeRect, 3.5f, 3.5f, isCredit ? statusUnpaidBorderPaint : statusPaidBorderPaint);
                                        canvas.drawText(badgeText, badgeRect.left + 7, badgeRect.top + 10.5f, payTextPaint);

                                        // =========================================================================
                                        // 3. TABLE HEADER BAR (CLEAN 5-COL FOR RETAIL, 8-COL FOR GST)
                                        // =========================================================================
                                        float thTop = custTop + custHeight + 8;
                                        float thHeight = 20;
                                        RectF thRect = new RectF(leftX, thTop, rightX, thTop + thHeight);
                                        canvas.drawRoundRect(thRect, 4, 4, thBgPaint);
                                        if (showStatutoryGstColumns) {
                                            canvas.drawText("#", 42, thTop + 13, thTextPaint);
                                            canvas.drawText("ITEM DESCRIPTION", 58, thTop + 13, thTextPaint);
                                            canvas.drawText("HSN", 232, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "QTY", 295, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "RATE", 350, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TAXABLE", 415, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "GST", 480, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TOTAL (₹)", rightX - 8, thTop + 13, thTextPaint);
                                        } else {
                                            canvas.drawText("#", 44, thTop + 13, thTextPaint);
                                            canvas.drawText("ITEM DESCRIPTION", 64, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "QTY", 360, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "RATE", 445, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TOTAL (₹)", rightX - 8, thTop + 13, thTextPaint);
                                        }

                                        currentY = thTop + thHeight + 14;
                                    } else {
                                        // --- CONTINUATION PAGES (PAGE 2+) ---
                                        canvas.drawText(safeEllipsize(storeName, storeNamePaint, 200), leftX, 46, storeNamePaint);
                                        canvas.drawText(headingText + " (Continued - Page " + pageIdx + " of " + totalPages + ")", 215, 46, subPaint);
                                        drawRightAlignedText(canvas, "#" + invoiceNumber, rightX, 46, docMetaBoldPaint);
                                        canvas.drawLine(leftX, 54, rightX, 54, linePaint);

                                        boolean isB2B = customerGstin != null && !customerGstin.trim().isEmpty();
                                        boolean hasTaxBreakup = taxBreakup != null && !taxBreakup.isEmpty();
                                        boolean hasGst = taxAmount != null && !taxAmount.trim().isEmpty() && !taxAmount.equals("₹0.00") && !taxAmount.equals("₹0");
                                        boolean showStatutoryGstColumns = isB2B || hasTaxBreakup || hasGst;

                                        float thTop = 60;
                                        float thHeight = 20;
                                        RectF thRect = new RectF(leftX, thTop, rightX, thTop + thHeight);
                                        canvas.drawRoundRect(thRect, 4, 4, thBgPaint);
                                        if (showStatutoryGstColumns) {
                                            canvas.drawText("#", 42, thTop + 13, thTextPaint);
                                            canvas.drawText("ITEM DESCRIPTION", 58, thTop + 13, thTextPaint);
                                            canvas.drawText("HSN", 232, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "QTY", 295, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "RATE", 350, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TAXABLE", 415, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "GST", 480, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TOTAL (₹)", rightX - 8, thTop + 13, thTextPaint);
                                        } else {
                                            canvas.drawText("#", 44, thTop + 13, thTextPaint);
                                            canvas.drawText("ITEM DESCRIPTION", 64, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "QTY", 360, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "RATE", 445, thTop + 13, thTextPaint);
                                            drawRightAlignedText(canvas, "TOTAL (₹)", rightX - 8, thTop + 13, thTextPaint);
                                        }

                                        currentY = thTop + thHeight + 14;
                                    }

                                    boolean isB2B = customerGstin != null && !customerGstin.trim().isEmpty();
                                    boolean hasTaxBreakup = taxBreakup != null && !taxBreakup.isEmpty();
                                    boolean hasGst = taxAmount != null && !taxAmount.trim().isEmpty() && !taxAmount.equals("₹0.00") && !taxAmount.equals("₹0");
                                    boolean showStatutoryGstColumns = isB2B || hasTaxBreakup || hasGst;

                                    // Render Items for this page with Unicode/Indic safe wrapping & right-aligned numbers
                                    List<Map<String, Object>> pageItems = pagesItems.get(pageIdx - 1);
                                    int rowCount = 0;
                                    float rowHeight = 19.5f;

                                    for (Map<String, Object> item : pageItems) {
                                        String name = String.valueOf(item.get("name"));
                                        String hsn = item.containsKey("hsn") && item.get("hsn") != null ? String.valueOf(item.get("hsn")) : "-";
                                        String qty = String.valueOf(item.get("qty"));
                                        String rate = String.valueOf(item.get("rate"));
                                        String taxable = item.containsKey("taxable") && item.get("taxable") != null ? String.valueOf(item.get("taxable")) : rate;
                                        String taxAmt = item.containsKey("taxAmt") && item.get("taxAmt") != null ? String.valueOf(item.get("taxAmt")) : "₹0.00";
                                        String amt = String.valueOf(item.get("amount"));

                                        if (rowCount % 2 == 1) {
                                            RectF altBg = new RectF(leftX, currentY - 10.5f, rightX, currentY + 7.5f);
                                            canvas.drawRect(altBg, rowAltBgPaint);
                                        }

                                        if (showStatutoryGstColumns) {
                                            canvas.drawText(String.valueOf(globalSNo++), 42, currentY, subPaint);
                                            canvas.drawText(safeEllipsize(name, itemNamePaint, 170), 58, currentY, itemNamePaint);
                                            canvas.drawText(safeEllipsize(hsn, bodyPaint, 45), 232, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, qty, 295, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, rate, 350, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, taxable, 415, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, taxAmt, 480, currentY, subPaint);
                                            drawRightAlignedText(canvas, amt, rightX - 8, currentY, boldTextPaint);
                                        } else {
                                            canvas.drawText(String.valueOf(globalSNo++), 44, currentY, subPaint);
                                            canvas.drawText(safeEllipsize(name, itemNamePaint, 280), 64, currentY, itemNamePaint);
                                            drawRightAlignedText(canvas, qty, 360, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, rate, 445, currentY, bodyPaint);
                                            drawRightAlignedText(canvas, amt, rightX - 8, currentY, boldTextPaint);
                                        }

                                        canvas.drawLine(leftX, currentY + 7.5f, rightX, currentY + 7.5f, rowLinePaint);
                                        currentY += rowHeight;
                                        rowCount++;
                                    }

                                    // =========================================================================
                                    // LAST PAGE: STATUTORY GST SUMMARY, TOTALS, UPI, TERMS & SIGNATORY
                                    // =========================================================================
                                    if (pageIdx == totalPages) {
                                        canvas.drawLine(leftX, currentY, rightX, currentY, linePaint);
                                        currentY += 9;

                                        // 1. Amount in Words Box
                                        if (amountInWords != null && !amountInWords.trim().isEmpty()) {
                                            RectF wordsBox = new RectF(leftX, currentY, rightX, currentY + 17);
                                            canvas.drawRoundRect(wordsBox, 4, 4, cardBgPaint);
                                            canvas.drawRoundRect(wordsBox, 4, 4, cardBorderPaint);
                                            Paint wordsLabel = new Paint(boldTextPaint);
                                            wordsLabel.setTextSize(7.5f);
                                            canvas.drawText("Amount in Words: ", leftX + 8, currentY + 11.5f, wordsLabel);
                                            float prefixW = wordsLabel.measureText("Amount in Words: ");
                                            Paint wordsPaint = new Paint(bodyPaint);
                                            wordsPaint.setTextSize(7.5f);
                                            canvas.drawText(safeEllipsize(amountInWords, wordsPaint, rightX - leftX - prefixW - 20), leftX + 8 + prefixW, currentY + 11.5f, wordsPaint);
                                            currentY += 23;
                                        }

                                        // 2. Statutory GST Tax Slab Breakup Table (if taxBreakup available)
                                        if (taxBreakup != null && !taxBreakup.isEmpty()) {
                                            Paint gstThPaint = new Paint();
                                            gstThPaint.setColor(Color.rgb(241, 245, 249));
                                            RectF gstThRect = new RectF(leftX, currentY, rightX, currentY + 14);
                                            canvas.drawRoundRect(gstThRect, 3, 3, gstThPaint);

                                            Paint gstLabelPaint = new Paint(subPaint);
                                            gstLabelPaint.setTextSize(7f);
                                            gstLabelPaint.setTypeface(boldTypeface);
                                            canvas.drawText("HSN/SAC (RATE)", leftX + 6, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "TAXABLE VAL", 215, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "CGST RATE", 280, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "CGST AMT", 350, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "SGST RATE", 415, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "SGST AMT", 485, currentY + 10f, gstLabelPaint);
                                            drawRightAlignedText(canvas, "TOTAL TAX", rightX - 8, currentY + 10f, gstLabelPaint);

                                            currentY += 16;
                                            Paint gstRowPaint = new Paint(bodyPaint);
                                            gstRowPaint.setTextSize(7.5f);

                                            for (Map<String, Object> slab : taxBreakup) {
                                                String sHsn = String.valueOf(slab.get("hsn"));
                                                String sTaxable = String.valueOf(slab.get("taxable"));
                                                String sCgstRate = String.valueOf(slab.get("cgstRate"));
                                                String sCgstAmt = String.valueOf(slab.get("cgstAmt"));
                                                String sSgstRate = String.valueOf(slab.get("sgstRate"));
                                                String sSgstAmt = String.valueOf(slab.get("sgstAmt"));
                                                String sTotTax = String.valueOf(slab.get("totalTax"));

                                                canvas.drawText(safeEllipsize(sHsn, gstRowPaint, 110), leftX + 6, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sTaxable, 215, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sCgstRate, 280, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sCgstAmt, 350, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sSgstRate, 415, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sSgstAmt, 485, currentY, gstRowPaint);
                                                drawRightAlignedText(canvas, sTotTax, rightX - 8, currentY, gstRowPaint);

                                                currentY += 11.5f;
                                            }
                                            currentY += 4;
                                        }

                                        // 3. Bottom Two-Column Split (Left: UPI QR & Terms, Right: Totals & Signatory)
                                        float sectionTopY = currentY;

                                        // --- LEFT COLUMN (X: leftX to leftX + 270) ---
                                        float afterUpiY = sectionTopY;
                                        if (showDynamicUpiQr && !upiId.trim().isEmpty()) {
                                            float upiBoxHeight = 52;
                                            float upiBoxWidth = 270;
                                            RectF upiBox = new RectF(leftX, sectionTopY, leftX + upiBoxWidth, sectionTopY + upiBoxHeight);
                                            canvas.drawRoundRect(upiBox, 6, 6, cardBgPaint);
                                            canvas.drawRoundRect(upiBox, 6, 6, cardBorderPaint);

                                            float textStartX = leftX + 10;
                                            if (qrBmp != null) {
                                                RectF qrRect = new RectF(leftX + 6, sectionTopY + 5, leftX + 48, sectionTopY + 47);
                                                Paint bmpPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
                                                canvas.drawBitmap(qrBmp, null, qrRect, bmpPaint);
                                                textStartX = leftX + 54;
                                            }

                                            Paint upiTitlePaint = new Paint(boldTextPaint);
                                            upiTitlePaint.setTextSize(8.5f);
                                            canvas.drawText("Scan & Pay via UPI", textStartX, sectionTopY + 15, upiTitlePaint);

                                            Paint upiIdPaint = new Paint(subPaint);
                                            upiIdPaint.setTextSize(7.5f);
                                            String displayUpi = upiId.length() > 28 ? upiId.substring(0, 26) + "..." : upiId;
                                            canvas.drawText("UPI VPA: " + displayUpi, textStartX, sectionTopY + 27, upiIdPaint);

                                            Paint upiFree = new Paint(statusPaidTextPaint);
                                            upiFree.setTextSize(7f);
                                            canvas.drawText("✓ Verified Merchant • GPay/PhonePe/Paytm", textStartX, sectionTopY + 39, upiFree);

                                            afterUpiY = sectionTopY + upiBoxHeight + 6;
                                        }

                                        canvas.drawText("Terms & Conditions:", leftX, afterUpiY + 10, boldTextPaint);
                                        String[] termLines = termsText.split("\n");
                                        float tY = afterUpiY + 21;
                                        for (int tl = 0; tl < termLines.length && tl < 2; tl++) {
                                            String line = termLines[tl];
                                            canvas.drawText(safeEllipsize(line, subPaint, 260), leftX, tY, subPaint);
                                            tY += 10;
                                        }
                                        if (footerNote != null && !footerNote.trim().isEmpty()) {
                                            Paint notePaint = new Paint(subPaint);
                                            notePaint.setTextSize(7.5f);
                                            notePaint.setColor(Color.rgb(71, 85, 105));
                                            canvas.drawText("♥ " + safeEllipsize(footerNote, notePaint, 260), leftX, tY + 8, notePaint);
                                        }

                                        // --- RIGHT COLUMN (Totals & Signatory) ---
                                        float totalsX = 330;
                                        float totalsY = sectionTopY;

                                        // Subtotal
                                        String subtotalLabel = showStatutoryGstColumns ? "Taxable Value:" : "Subtotal:";
                                        canvas.drawText(subtotalLabel, totalsX, totalsY + 9, subPaint);
                                        drawRightAlignedText(canvas, taxableSubtotal, rightX - 8, totalsY + 9, bodyPaint);
                                        totalsY += 13;

                                        if (discountAmount != null && !discountAmount.isEmpty() && !discountAmount.equals("₹0.00") && !discountAmount.equals("0")) {
                                            canvas.drawText("Discount:", totalsX, totalsY + 9, subPaint);
                                            String discStr = "-" + discountAmount;
                                            drawRightAlignedText(canvas, discStr, rightX - 8, totalsY + 9, discountTextPaint);
                                            totalsY += 13;
                                        }

                                        if (taxAmount != null && !taxAmount.isEmpty() && !taxAmount.equals("₹0.00") && !taxAmount.equals("0")) {
                                            canvas.drawText("Total GST Tax:", totalsX, totalsY + 9, subPaint);
                                            drawRightAlignedText(canvas, taxAmount, rightX - 8, totalsY + 9, bodyPaint);
                                            totalsY += 13;
                                        }

                                        // Grand Total Box
                                        RectF gtBox = new RectF(totalsX - 4, totalsY + 2, rightX, totalsY + 32);
                                        canvas.drawRoundRect(gtBox, 5, 5, grandTotalBg);

                                        Paint gtLabel = new Paint(thTextPaint);
                                        gtLabel.setTextSize(9f);
                                        canvas.drawText("GRAND TOTAL", totalsX + 8, totalsY + 20, gtLabel);

                                        Paint gtVal = new Paint();
                                        gtVal.setColor(Color.WHITE);
                                        gtVal.setTextSize(13f);
                                        gtVal.setTypeface(boldTypeface);
                                        gtVal.setAntiAlias(true);
                                        gtVal.setSubpixelText(true);
                                        gtVal.setLinearText(true);
                                        drawRightAlignedText(canvas, totalAmount, rightX - 10, totalsY + 21, gtVal);

                                        // Authorised Signatory
                                        float signY = totalsY + 46;
                                        Paint signStoreName = new Paint(boldTextPaint);
                                        signStoreName.setTextSize(7.5f);
                                        canvas.drawText("For " + safeEllipsize(storeName, signStoreName, 170), 380, signY, signStoreName);

                                        canvas.drawLine(370, signY + 22, rightX, signY + 22, linePaint);
                                        Paint signLabel = new Paint(subPaint);
                                        signLabel.setTextSize(7f);
                                        signLabel.setTypeface(boldTypeface);
                                        drawRightAlignedText(canvas, "AUTHORISED SIGNATORY", rightX, signY + 31, signLabel);
                                    }

                                    // =========================================================================
                                    // KAMAI+ BRANDING STRIP WITH LOGO (ON EVERY PAGE)
                                    // =========================================================================
                                    float brandY = 776;
                                    RectF brandStrip = new RectF(leftX, brandY, rightX, brandY + 24);
                                    canvas.drawRoundRect(brandStrip, 5, 5, cardBgPaint);
                                    canvas.drawRoundRect(brandStrip, 5, 5, cardBorderPaint);

                                    float brandContentX = leftX + 8;
                                    if (appIconBmp != null) {
                                        RectF iconRect = new RectF(leftX + 6, brandY + 4, leftX + 22, brandY + 20);
                                        Paint iconPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
                                        canvas.drawBitmap(appIconBmp, null, iconRect, iconPaint);
                                        brandContentX = leftX + 28;
                                    }

                                    Paint brandTitle = new Paint();
                                    brandTitle.setColor(themeColor);
                                    brandTitle.setTextSize(8f);
                                    brandTitle.setTypeface(boldTypeface);
                                    brandTitle.setAntiAlias(true);
                                    canvas.drawText("⚡ KAMAI+ POS", brandContentX, brandY + 15, brandTitle);

                                    Paint brandDesc = new Paint();
                                    brandDesc.setColor(Color.rgb(71, 85, 105));
                                    brandDesc.setTextSize(7.5f);
                                    brandDesc.setTypeface(regularTypeface);
                                    brandDesc.setAntiAlias(true);
                                    canvas.drawText("• India's #1 Retail POS & GST Billing App", brandContentX + 66, brandY + 15, brandDesc);

                                    // Page Number Footer
                                    Paint pageNumPaint = new Paint(subPaint);
                                    pageNumPaint.setTextSize(7.5f);
                                    String pageStr = "Page " + pageIdx + " of " + totalPages;
                                    float pageW = pageNumPaint.measureText(pageStr);
                                    canvas.drawText(pageStr, 297.5f - (pageW / 2), 814, pageNumPaint);

                                    document.finishPage(page);
                                }

                                // 1. Save PDF to App Documents directory (Guaranteed 100% writable on all Android versions)
                                File docsDir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
                                if (docsDir == null) docsDir = getFilesDir();
                                if (!docsDir.exists()) docsDir.mkdirs();

                                String cleanInv = invoiceNumber.replaceAll("[^a-zA-Z0-9_-]", "_");
                                String fileName = "Kamai_Invoice_" + cleanInv + ".pdf";
                                File pdfFile = new File(docsDir, fileName);
                                FileOutputStream fos = new FileOutputStream(pdfFile);
                                document.writeTo(fos);
                                fos.flush();
                                fos.close();
                                document.close();
                                                     Boolean skipDownloadsFolder = call.argument("skipDownloadsFolder");
                                if (skipDownloadsFolder == null) skipDownloadsFolder = false;

                                if (!skipDownloadsFolder) {
                                    // 2. Also copy to public Downloads for user visibility across Files app
                                    try {
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                            ContentValues values = new ContentValues();
                                            values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
                                            values.put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf");
                                            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/KamaiPlus");
                                            Uri downloadUri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                                            if (downloadUri != null) {
                                                OutputStream os = getContentResolver().openOutputStream(downloadUri);
                                                if (os != null) {
                                                    FileInputStream fis = new FileInputStream(pdfFile);
                                                    byte[] buf = new byte[8192];
                                                    int len;
                                                    while ((len = fis.read(buf)) > 0) {
                                                        os.write(buf, 0, len);
                                                    }
                                                    fis.close();
                                                    os.flush();
                                                    os.close();
                                                }
                                            }
                                        } else {
                                            File pubDownloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                                            if (pubDownloads != null) {
                                                if (!pubDownloads.exists()) pubDownloads.mkdirs();
                                                File pubFile = new File(pubDownloads, fileName);
                                                FileInputStream fis = new FileInputStream(pdfFile);
                                                FileOutputStream pubFos = new FileOutputStream(pubFile);
                                                byte[] buf = new byte[8192];
                                                int len;
                                                while ((len = fis.read(buf)) > 0) {
                                                    pubFos.write(buf, 0, len);
                                                }
                                                fis.close();
                                                pubFos.flush();
                                                pubFos.close();
                                            }
                                        }
                                    } catch (Exception ignored) {
                                        // Primary file in docsDir is guaranteed saved
                                    }

                                    // Trigger Native Download Notification with Tap-to-Open
                                    Intent viewIntent = new Intent(Intent.ACTION_VIEW);
                                    Uri fileUri = FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", pdfFile);
                                    viewIntent.setDataAndType(fileUri, "application/pdf");
                                    viewIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);

                                    PendingIntent openPendingIntent = PendingIntent.getActivity(
                                            MainActivity.this,
                                            (int) System.currentTimeMillis(),
                                            viewIntent,
                                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0
                                    );

                                    NotificationCompat.Builder notif = new NotificationCompat.Builder(MainActivity.this, CHANNEL_ID)
                                            .setSmallIcon(R.mipmap.ic_launcher)
                                            .setContentTitle("Tax Invoice Downloaded 📥")
                                            .setContentText("Invoice #" + invoiceNumber + " (" + totalAmount + ") saved to Downloads.")
                                            .setStyle(new NotificationCompat.BigTextStyle().bigText("Invoice #" + invoiceNumber + " (" + totalAmount + ") saved to Downloads. Tap to view."))
                                            .setPriority(NotificationCompat.PRIORITY_HIGH)
                                            .setAutoCancel(true)
                                            .setContentIntent(openPendingIntent);

                                    NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                                    if (nm != null) {
                                        nm.notify((int) System.currentTimeMillis(), notif.build());
                                    }
                                }

                                result.success(pdfFile.getAbsolutePath());
                            } catch (Exception e) {
                                result.error("PDF_ERROR", e.getMessage(), null);
                            }
                        } else if ("generateAndSaveKhataStatementPdf".equals(call.method)) {
                            try {
                                String storeName = call.argument("storeName");
                                String storePhone = call.argument("storePhone");
                                String customerName = call.argument("customerName");
                                String customerPhone = call.argument("customerPhone");
                                String dateStr = call.argument("dateStr");
                                String totalBalance = call.argument("totalBalance");
                                String upiId = call.argument("upiId");
                                List<Map<String, Object>> transactions = call.argument("transactions");

                                if (storeName == null || storeName.trim().isEmpty()) storeName = "KamaiPlus Store";
                                if (customerName == null || customerName.trim().isEmpty()) customerName = "Customer";
                                if (customerPhone == null) customerPhone = "";
                                if (dateStr == null) dateStr = "";
                                if (totalBalance == null) totalBalance = "₹0.00";
                                if (upiId == null) upiId = "";
                                if (transactions == null) transactions = new ArrayList<>();

                                PdfDocument document = new PdfDocument();
                                PdfDocument.PageInfo pageInfo = new PdfDocument.PageInfo.Builder(595, 842, 1).create(); // A4
                                PdfDocument.Page page = document.startPage(pageInfo);
                                Canvas canvas = page.getCanvas();

                                Paint darkPaint = new Paint();
                                darkPaint.setColor(Color.rgb(15, 23, 42));
                                darkPaint.setTextSize(16);
                                darkPaint.setFakeBoldText(true);
                                darkPaint.setAntiAlias(true);

                                Paint subPaint = new Paint();
                                subPaint.setColor(Color.rgb(100, 116, 139));
                                subPaint.setTextSize(9);
                                subPaint.setAntiAlias(true);

                                Paint boldTextPaint = new Paint();
                                boldTextPaint.setColor(Color.rgb(15, 23, 42));
                                boldTextPaint.setTextSize(9.5f);
                                boldTextPaint.setFakeBoldText(true);
                                boldTextPaint.setAntiAlias(true);

                                Paint bodyPaint = new Paint();
                                bodyPaint.setColor(Color.rgb(30, 41, 59));
                                bodyPaint.setTextSize(9f);
                                bodyPaint.setAntiAlias(true);

                                Paint linePaint = new Paint();
                                linePaint.setColor(Color.rgb(226, 232, 240));
                                linePaint.setStrokeWidth(0.8f);

                                Paint rowLinePaint = new Paint();
                                rowLinePaint.setColor(Color.rgb(241, 245, 249));
                                rowLinePaint.setStrokeWidth(0.6f);

                                // Header background band
                                RectF headerRect = new RectF(36, 36, 559, 90);
                                Paint headerBg = new Paint();
                                headerBg.setColor(Color.rgb(238, 242, 255));
                                canvas.drawRoundRect(headerRect, 8, 8, headerBg);

                                canvas.drawText(storeName, 50, 60, darkPaint);
                                if (storePhone != null && !storePhone.isEmpty()) {
                                    canvas.drawText("Tel: " + storePhone, 50, 75, subPaint);
                                }

                                Paint rightTitle = new Paint(darkPaint);
                                rightTitle.setTextSize(13);
                                rightTitle.setColor(Color.rgb(79, 70, 229));
                                canvas.drawText("KHATA STATEMENT", 390, 60, rightTitle);
                                canvas.drawText("Date: " + dateStr, 390, 75, subPaint);

                                // Customer info
                                RectF custBox = new RectF(36, 102, 330, 155);
                                Paint custBg = new Paint();
                                custBg.setColor(Color.rgb(248, 250, 252));
                                canvas.drawRoundRect(custBox, 8, 8, custBg);
                                canvas.drawRoundRect(custBox, 8, 8, linePaint);

                                canvas.drawText("CUSTOMER DETAILS:", 46, 118, boldTextPaint);
                                canvas.drawText("Name: " + customerName, 46, 132, bodyPaint);
                                canvas.drawText("Phone: " + customerPhone, 46, 146, subPaint);

                                // Balance Highlight Pill
                                RectF balBox = new RectF(345, 102, 559, 155);
                                Paint balBg = new Paint();
                                balBg.setColor(Color.rgb(254, 242, 242));
                                canvas.drawRoundRect(balBox, 8, 8, balBg);
                                Paint balBorder = new Paint(linePaint);
                                balBorder.setColor(Color.rgb(254, 202, 202));
                                canvas.drawRoundRect(balBox, 8, 8, balBorder);

                                Paint balLabel = new Paint(subPaint);
                                balLabel.setColor(Color.rgb(185, 28, 28));
                                balLabel.setFakeBoldText(true);
                                canvas.drawText("NET BALANCE DUE", 360, 118, balLabel);

                                Paint balVal = new Paint();
                                balVal.setColor(Color.rgb(220, 38, 38));
                                balVal.setTextSize(16);
                                balVal.setFakeBoldText(true);
                                balVal.setAntiAlias(true);
                                canvas.drawText(totalBalance, 360, 142, balVal);

                                // Table Header
                                RectF thRect = new RectF(36, 168, 559, 190);
                                Paint thBg = new Paint();
                                thBg.setColor(Color.rgb(79, 70, 229));
                                canvas.drawRoundRect(thRect, 6, 6, thBg);

                                Paint thText = new Paint();
                                thText.setColor(Color.WHITE);
                                thText.setTextSize(8.5f);
                                thText.setFakeBoldText(true);
                                thText.setAntiAlias(true);

                                canvas.drawText("DATE & TIME", 46, 182, thText);
                                canvas.drawText("TYPE", 160, 182, thText);
                                canvas.drawText("NOTE / PARTICULARS", 240, 182, thText);
                                canvas.drawText("AMOUNT (₹)", 420, 182, thText);
                                canvas.drawText("BALANCE (₹)", 495, 182, thText);

                                float y = 208;
                                int count = 0;
                                for (Map<String, Object> tx : transactions) {
                                    if (count++ > 24) break;
                                    String txDate = String.valueOf(tx.get("date"));
                                    String txType = String.valueOf(tx.get("type"));
                                    String txNote = String.valueOf(tx.get("note"));
                                    String txAmt = String.valueOf(tx.get("amount"));
                                    String txBal = String.valueOf(tx.get("balance"));

                                    if (txDate.length() > 16) txDate = txDate.substring(0, 16);
                                    if (txNote.length() > 24) txNote = txNote.substring(0, 24) + "...";

                                    canvas.drawText(txDate, 46, y, subPaint);

                                    Paint typePaint = new Paint(bodyPaint);
                                    if (txType.toLowerCase().contains("credit") || txType.toLowerCase().contains("udhar")) {
                                        typePaint.setColor(Color.rgb(220, 38, 38));
                                        typePaint.setFakeBoldText(true);
                                    } else {
                                        typePaint.setColor(Color.rgb(22, 163, 74));
                                        typePaint.setFakeBoldText(true);
                                    }
                                    canvas.drawText(txType.toUpperCase(), 160, y, typePaint);
                                    canvas.drawText(txNote, 240, y, bodyPaint);
                                    canvas.drawText(txAmt, 420, y, boldTextPaint);
                                    canvas.drawText(txBal, 495, y, boldTextPaint);

                                    canvas.drawLine(36, y + 4, 559, y + 4, rowLinePaint);
                                    y += 18;
                                }

                                // Bottom Payment box (only if store has a configured UPI VPA)
                                if (!upiId.trim().isEmpty()) {
                                    float bY = Math.max(y + 15, 730);
                                    RectF upiBox = new RectF(36, bY, 559, bY + 48);
                                    Paint upiBg = new Paint();
                                    upiBg.setColor(Color.rgb(240, 253, 244));
                                    canvas.drawRoundRect(upiBox, 6, 6, upiBg);
                                    canvas.drawRoundRect(upiBox, 6, 6, linePaint);

                                    canvas.drawText("Instant UPI Settlement: " + upiId, 50, bY + 20, boldTextPaint);
                                    canvas.drawText("Pay online directly using PhonePe, GPay, Paytm or BHIM UPI to clear balance.", 50, bY + 34, subPaint);
                                }

                                // Footer
                                canvas.drawText("Generated via KamaiPlus POS System • Single Source of Truth", 160, 810, subPaint);

                                document.finishPage(page);

                                File docsDir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
                                if (docsDir == null) docsDir = getFilesDir();
                                String cleanPhone = customerPhone.replaceAll("[^0-9]", "");
                                File pdfFile = new File(docsDir, "Khata_Statement_" + (cleanPhone.isEmpty() ? System.currentTimeMillis() : cleanPhone) + ".pdf");
                                FileOutputStream fos = new FileOutputStream(pdfFile);
                                document.writeTo(fos);
                                document.close();
                                fos.close();

                                result.success(pdfFile.getAbsolutePath());
                            } catch (Exception e) {
                                result.error("KHATA_PDF_ERROR", e.getMessage(), null);
                            }
                        } else if ("openPdf".equals(call.method)) {
                            try {
                                String path = call.argument("path");
                                if (path != null) {
                                    File file = new File(path);
                                    if (file.exists()) {
                                        Intent intent = new Intent(Intent.ACTION_VIEW);
                                        Uri uri = FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", file);
                                        intent.setDataAndType(uri, "application/pdf");
                                        intent.setClipData(ClipData.newRawUri("Invoice PDF", uri));
                                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                                        try {
                                            List<ResolveInfo> resInfoList = getPackageManager().queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY);
                                            for (ResolveInfo resolveInfo : resInfoList) {
                                                grantUriPermission(resolveInfo.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                            }
                                        } catch (Exception ignored) {}
                                        startActivity(intent);
                                        result.success(true);
                                        return;
                                    }
                                }
                                result.success(false);
                            } catch (Exception e) {
                                result.error("OPEN_ERROR", e.getMessage(), null);
                            }
                        } else if ("printPdf".equals(call.method)) {
                            try {
                                final String path = call.argument("path");
                                String name = call.argument("name");
                                if (name == null || name.isEmpty()) name = "Tax_Invoice";
                                final String docName = name;
                                if (path != null) {
                                    final File file = new File(path);
                                    if (file.exists()) {
                                        final PrintManager printManager = (PrintManager) getSystemService(Context.PRINT_SERVICE);
                                        if (printManager != null) {
                                            runOnUiThread(new Runnable() {
                                                @Override
                                                public void run() {
                                                    try {
                                                        PrintDocumentAdapter pda = new PrintDocumentAdapter() {
                                                            @Override
                                                            public void onLayout(PrintAttributes oldAttributes, PrintAttributes newAttributes,
                                                                                 CancellationSignal cancellationSignal,
                                                                                 LayoutResultCallback callback, Bundle extras) {
                                                                if (cancellationSignal.isCanceled()) {
                                                                    callback.onLayoutCancelled();
                                                                    return;
                                                                }
                                                                PrintDocumentInfo info = new PrintDocumentInfo.Builder(file.getName())
                                                                        .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                                                        .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN)
                                                                        .build();
                                                                callback.onLayoutFinished(info, !newAttributes.equals(oldAttributes));
                                                            }

                                                            @Override
                                                            public void onWrite(PageRange[] pages, ParcelFileDescriptor destination,
                                                                                CancellationSignal cancellationSignal,
                                                                                WriteResultCallback callback) {
                                                                try (InputStream in = new FileInputStream(file);
                                                                     OutputStream out = new FileOutputStream(destination.getFileDescriptor())) {
                                                                    byte[] buf = new byte[8192];
                                                                    int bytesRead;
                                                                    while ((bytesRead = in.read(buf)) > 0) {
                                                                        if (cancellationSignal.isCanceled()) {
                                                                            callback.onWriteCancelled();
                                                                            return;
                                                                        }
                                                                        out.write(buf, 0, bytesRead);
                                                                    }
                                                                    callback.onWriteFinished(new PageRange[]{PageRange.ALL_PAGES});
                                                                } catch (Exception e) {
                                                                    callback.onWriteFailed(e.getMessage());
                                                                }
                                                            }
                                                        };
                                                        printManager.print(docName, pda, new PrintAttributes.Builder().build());
                                                    } catch (Exception ignored) {}
                                                }
                                            });
                                            result.success(true);
                                            return;
                                        }
                                    }
                                }
                                result.success(false);
                            } catch (Exception e) {
                                result.error("PRINT_PDF_ERROR", e.getMessage(), null);
                            }
                        } else if ("sharePdf".equals(call.method)) {
                            try {
                                String path = call.argument("path");
                                String invNum = call.argument("invoiceNumber");
                                String sName = call.argument("storeName");
                                String phone = call.argument("phone");
                                String message = call.argument("message");
                                String subject = call.argument("subject");
                                Boolean forceChooser = call.argument("forceChooser");
                                if (forceChooser == null) forceChooser = false;

                                if (invNum == null) invNum = "DOC";
                                if (sName == null) sName = "KamaiPlus";
                                if (subject == null || subject.isEmpty()) {
                                    subject = "Document #" + invNum + " - " + sName;
                                }

                                if (path != null) {
                                    File file = new File(path);
                                    if (file.exists()) {
                                        Uri uri = FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", file);
                                        Intent shareIntent = new Intent(Intent.ACTION_SEND);
                                        shareIntent.setType("application/pdf");
                                        shareIntent.putExtra(Intent.EXTRA_STREAM, uri);
                                        shareIntent.setClipData(ClipData.newRawUri("Invoice PDF", uri));
                                        shareIntent.putExtra(Intent.EXTRA_SUBJECT, subject);
                                        if (message != null && !message.trim().isEmpty()) {
                                            shareIntent.putExtra(Intent.EXTRA_TEXT, message);
                                        } else {
                                            shareIntent.putExtra(Intent.EXTRA_TEXT, "Hello! Here is your document #" + invNum + " from " + sName + ".");
                                        }
                                        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);

                                        // Direct WhatsApp share only if explicitly requested without forceChooser
                                        if (!forceChooser && phone != null && !phone.trim().isEmpty()) {
                                            String cleanPhone = phone.replaceAll("[^0-9]", "");
                                            if (cleanPhone.startsWith("9191") && cleanPhone.length() == 14) {
                                                cleanPhone = cleanPhone.substring(2);
                                            } else if (cleanPhone.startsWith("0") && cleanPhone.length() == 11) {
                                                cleanPhone = "91" + cleanPhone.substring(1);
                                            } else if (cleanPhone.length() == 10) {
                                                cleanPhone = "91" + cleanPhone;
                                            }
                                            boolean hasValidJid = cleanPhone.length() == 12;
                                            
                                            // 1. Try standard WhatsApp
                                            try {
                                                grantUriPermission("com.whatsapp", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                                Intent waIntent = new Intent(shareIntent);
                                                waIntent.setPackage("com.whatsapp");
                                                if (hasValidJid) {
                                                    waIntent.putExtra("jid", cleanPhone + "@s.whatsapp.net");
                                                }
                                                startActivity(waIntent);
                                                result.success(true);
                                                return;
                                            } catch (Exception waEx) {
                                                // 2. Try WhatsApp Business
                                                try {
                                                    grantUriPermission("com.whatsapp.w4b", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                                    Intent wabIntent = new Intent(shareIntent);
                                                    wabIntent.setPackage("com.whatsapp.w4b");
                                                    if (hasValidJid) {
                                                        wabIntent.putExtra("jid", cleanPhone + "@s.whatsapp.net");
                                                    }
                                                    startActivity(wabIntent);
                                                    result.success(true);
                                                    return;
                                                } catch (Exception wabEx) {
                                                    // Fallback to chooser below
                                                }
                                            }
                                        }

                                        // System Share Dialog
                                        Intent chooser = Intent.createChooser(shareIntent, "Share Document PDF via...");
                                        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                                        try {
                                            List<ResolveInfo> resInfoList = getPackageManager().queryIntentActivities(chooser, PackageManager.MATCH_DEFAULT_ONLY);
                                            for (ResolveInfo resolveInfo : resInfoList) {
                                                grantUriPermission(resolveInfo.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                            }
                                        } catch (Exception ignored) {}
                                        startActivity(chooser);
                                        result.success(true);
                                        return;
                                    }
                                }
                                result.success(false);
                            } catch (Exception e) {
                                result.error("SHARE_ERROR", e.getMessage(), null);
                            }
                        } else {
                            result.notImplemented();
                        }
                    }
                });

        // 9. Real-Time UPI Payment Notification & Soundbox Detector Engine
        paymentDetectorChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PAYMENT_DETECTOR_CHANNEL);
        PaymentNotificationListener.setCallback(new PaymentNotificationListener.PaymentCallback() {
            @Override
            public void onPaymentDetected(long amountPaise, String appName, String sender, String rawText) {
                forwardPaymentToFlutter(amountPaise, appName, sender, rawText);
            }
        });

        paymentDetectorChannel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
            @Override
            public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                if ("isNotificationAccessGranted".equals(call.method)) {
                    result.success(isNotificationServiceEnabled());
                } else if ("openNotificationAccessSettings".equals(call.method)) {
                    try {
                        Intent intent = new Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.success(false);
                    }
                } else if ("simulatePayment".equals(call.method)) {
                    try {
                        Object amtObj = call.argument("amountPaise");
                        long amountPaise = 0;
                        if (amtObj instanceof Number) {
                            amountPaise = ((Number) amtObj).longValue();
                        }
                        String appName = call.argument("appName");
                        if (appName == null || appName.isEmpty()) appName = "PhonePe";
                        forwardPaymentToFlutter(amountPaise, appName, "Simulator Test", "₹" + (amountPaise / 100.0) + " received");
                        result.success(true);
                    } catch (Exception e) {
                        result.error("SIMULATION_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            }
        });
    }

    private boolean isNotificationServiceEnabled() {
        try {
            String pkgName = getPackageName();
            final String flat = android.provider.Settings.Secure.getString(getContentResolver(), "enabled_notification_listeners");
            if (flat != null && !flat.isEmpty()) {
                final String[] names = flat.split(":");
                for (String name : names) {
                    final android.content.ComponentName cn = android.content.ComponentName.unflattenFromString(name);
                    if (cn != null && pkgName.equals(cn.getPackageName())) {
                        return true;
                    }
                }
            }
        } catch (Exception ignored) {}
        return false;
    }

    @Override
    public void onInit(int status) {
        if (status == TextToSpeech.SUCCESS) {
            tts.setLanguage(new Locale("hi", "IN"));
            tts.setSpeechRate(0.95f);
            isTtsReady = true;
            if (pendingSpeakText != null) {
                Locale locale = "hi".equals(pendingSpeakLang) ? new Locale("hi", "IN") : new Locale("en", "IN");
                tts.setLanguage(locale);
                tts.speak(pendingSpeakText, TextToSpeech.QUEUE_FLUSH, null, "KAMAI_TTS");
                pendingSpeakText = null;
                pendingSpeakLang = null;
            }
        }
    }

    private void forwardPaymentToFlutter(final long amountPaise, final String appName, final String sender, final String rawText) {
        if (paymentDetectorChannel != null) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    Map<String, Object> map = new HashMap<>();
                    map.put("amountPaise", amountPaise);
                    map.put("appName", appName);
                    map.put("sender", sender != null ? sender : "");
                    map.put("rawText", rawText != null ? rawText : "");
                    map.put("timestamp", System.currentTimeMillis());
                    paymentDetectorChannel.invokeMethod("onPaymentDetected", map);
                }
            });
        }
    }

    /**
     * Short high beep for a good scan, low buzz for a problem. ToneGenerator
     * can throw if the audio system is busy; the Dart side then falls back to
     * the system click, so a scan never fails because of sound.
     */
    private boolean playScanBeep(boolean isError) {
        try {
            if (scanTone == null) {
                scanTone = new ToneGenerator(AudioManager.STREAM_MUSIC, 85);
            }
            if (isError) {
                scanTone.startTone(ToneGenerator.TONE_SUP_ERROR, 280);
            } else {
                scanTone.startTone(ToneGenerator.TONE_PROP_BEEP, 120);
            }
            return true;
        } catch (RuntimeException e) {
            scanTone = null;
            return false;
        }
    }

    @Override
    protected void onDestroy() {
        PaymentNotificationListener.setCallback(null);
        if (scanTone != null) {
            scanTone.release();
            scanTone = null;
        }
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
        super.onDestroy();
    }
}
