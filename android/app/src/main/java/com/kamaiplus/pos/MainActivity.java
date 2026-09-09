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
import android.os.Environment;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.database.Cursor;
import android.speech.tts.TextToSpeech;
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
    private static final String CHANNEL_ID = "kamai_pos_channel";
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
    private static final int REQUEST_CODE_PICK_CONTACT = 5001;

    private TextToSpeech tts;
    private boolean isTtsReady = false;
    private String pendingSpeakText = null;
    private String pendingSpeakLang = null;
    private MethodChannel.Result pendingContactResult;
    private String pendingShortcut = null;
    private String pendingSharedFile = null;
    private MethodChannel shortcutMethodChannel;
    private MethodChannel shareMethodChannel;

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
                                String logoPath = call.argument("logoPath");
                                String customerName = call.argument("customerName");
                                String customerPhone = call.argument("customerPhone");
                                String dateStr = call.argument("dateStr");
                                String paymentMode = call.argument("paymentMode");
                                String subtotalAmount = call.argument("subtotalAmount");
                                String discountAmount = call.argument("discountAmount");
                                String taxAmount = call.argument("taxAmount");
                                String totalAmount = call.argument("totalAmount");
                                List<Map<String, Object>> items = call.argument("items");
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

                                if (invoiceNumber == null) invoiceNumber = "INV-" + System.currentTimeMillis();
                                if (storeName == null || storeName.trim().isEmpty()) storeName = "KamaiPlus Store";
                                if (customerName == null || customerName.trim().isEmpty()) customerName = "Cash Customer";
                                if (dateStr == null) dateStr = "";
                                if (paymentMode == null) paymentMode = "CASH";
                                if (totalAmount == null) totalAmount = "₹0.00";
                                if (subtotalAmount == null) subtotalAmount = totalAmount;
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

                                // Paints
                                Paint darkPaint = new Paint();
                                darkPaint.setColor(Color.rgb(15, 23, 42)); // Slate 900
                                darkPaint.setTextSize(16);
                                darkPaint.setFakeBoldText(true);
                                darkPaint.setAntiAlias(true);

                                Paint subPaint = new Paint();
                                subPaint.setColor(Color.rgb(100, 116, 139)); // Slate 500
                                subPaint.setTextSize(9);
                                subPaint.setAntiAlias(true);

                                Paint bodyPaint = new Paint();
                                bodyPaint.setColor(Color.rgb(30, 41, 59)); // Slate 800
                                bodyPaint.setTextSize(9.5f);
                                bodyPaint.setAntiAlias(true);

                                Paint boldTextPaint = new Paint();
                                boldTextPaint.setColor(Color.rgb(15, 23, 42));
                                boldTextPaint.setTextSize(9.5f);
                                boldTextPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                                boldTextPaint.setAntiAlias(true);

                                Paint itemNamePaint = new Paint();
                                itemNamePaint.setColor(Color.rgb(15, 23, 42));
                                itemNamePaint.setTextSize(9.5f);
                                itemNamePaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                                itemNamePaint.setAntiAlias(true);
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                    itemNamePaint.setLetterSpacing(0.012f);
                                }

                                Paint linePaint = new Paint();
                                linePaint.setColor(Color.rgb(226, 232, 240)); // Slate 200
                                linePaint.setStrokeWidth(0.8f);

                                Paint rowLinePaint = new Paint();
                                rowLinePaint.setColor(Color.rgb(241, 245, 249)); // Slate 100
                                rowLinePaint.setStrokeWidth(0.6f);

                                Paint thBgPaint = new Paint();
                                thBgPaint.setColor(themeColor); // Live theme color

                                Paint thTextPaint = new Paint();
                                thTextPaint.setColor(Color.WHITE);
                                thTextPaint.setTextSize(9f);
                                thTextPaint.setFakeBoldText(true);
                                thTextPaint.setAntiAlias(true);

                                Paint badgeBg = new Paint();
                                badgeBg.setColor(Color.rgb(241, 245, 249));

                                Paint grandTotalBg = new Paint();
                                grandTotalBg.setColor(themeColor); // Live theme color

                                // Load Store Logo Bitmap if present
                                Bitmap logoBmp = null;
                                if (logoPath != null && !logoPath.trim().isEmpty()) {
                                    try {
                                        File lf = new File(logoPath);
                                        if (lf.exists() && lf.length() > 0) {
                                            BitmapFactory.Options opts = new BitmapFactory.Options();
                                            opts.inPreferredConfig = Bitmap.Config.RGB_565;
                                            logoBmp = BitmapFactory.decodeFile(logoPath, opts);
                                        }
                                    } catch (Exception ignored) {}
                                }

                                // Multi-page Calculation
                                List<List<Map<String, Object>>> pagesItems = new ArrayList<>();
                                int itemIndex = 0;
                                int totalItems = items.size();

                                // Page 1 items (header height ~170pt)
                                List<Map<String, Object>> p1Items = new ArrayList<>();
                                int p1Limit = (totalItems <= 21) ? totalItems : 25;
                                for (int i = 0; i < p1Limit && itemIndex < totalItems; i++) {
                                    p1Items.add(items.get(itemIndex++));
                                }
                                pagesItems.add(p1Items);

                                // Subsequent pages
                                while (itemIndex < totalItems) {
                                    List<Map<String, Object>> nextP = new ArrayList<>();
                                    int remaining = totalItems - itemIndex;
                                    int nextLimit = (remaining <= 25) ? remaining : 30;
                                    for (int i = 0; i < nextLimit && itemIndex < totalItems; i++) {
                                        nextP.add(items.get(itemIndex++));
                                    }
                                    pagesItems.add(nextP);
                                }

                                int totalPages = pagesItems.size();
                                PdfDocument document = new PdfDocument();

                                int globalSNo = 1;
                                for (int pageIdx = 1; pageIdx <= totalPages; pageIdx++) {
                                    PdfDocument.PageInfo pageInfo = new PdfDocument.PageInfo.Builder(595, 842, pageIdx).create();
                                    PdfDocument.Page page = document.startPage(pageInfo);
                                    Canvas canvas = page.getCanvas();

                                    int currentY;

                                    if (pageIdx == 1) {
                                        // --- PAGE 1 FULL THEMED HEADER (MATCHING LIVE INTERACTIVE PREVIEW) ---
                                        // 1. Theme-colored Header Banner Block
                                        RectF headerBanner = new RectF(36, 36, 559, 102);
                                        canvas.drawRoundRect(headerBanner, 10, 10, thBgPaint);

                                        float textLeft = 48;
                                        if (logoBmp != null) {
                                            RectF logoRect = new RectF(46, 44, 86, 84);
                                            Paint bmpPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
                                            canvas.drawBitmap(logoBmp, null, logoRect, bmpPaint);
                                            textLeft = 96;
                                        }

                                        // Store Details in white
                                        Paint whiteStoreName = new Paint();
                                        whiteStoreName.setColor(Color.WHITE);
                                        whiteStoreName.setTextSize(14.5f);
                                        whiteStoreName.setFakeBoldText(true);
                                        whiteStoreName.setAntiAlias(true);

                                        Paint whiteSubPaint = new Paint();
                                        whiteSubPaint.setColor(Color.argb(225, 255, 255, 255));
                                        whiteSubPaint.setTextSize(8.5f);
                                        whiteSubPaint.setAntiAlias(true);

                                        canvas.drawText(storeName.toUpperCase(), textLeft, 55, whiteStoreName);
                                        float storeSubY = 69;
                                        if (storeAddress != null && !storeAddress.trim().isEmpty()) {
                                            String addr = storeAddress.length() > 38 ? storeAddress.substring(0, 38) + "..." : storeAddress;
                                            canvas.drawText(addr, textLeft, storeSubY, whiteSubPaint);
                                            storeSubY += 12;
                                        }
                                        String contactInfo = "";
                                        if (storePhone != null && !storePhone.trim().isEmpty()) contactInfo += "Ph: " + storePhone + "  ";
                                        if (gstin != null && !gstin.trim().isEmpty()) contactInfo += "GSTIN: " + gstin;
                                        if (!contactInfo.isEmpty()) {
                                            canvas.drawText(contactInfo, textLeft, storeSubY, whiteSubPaint);
                                        }

                                        // Top Right Header Card inside banner
                                        RectF invBadge = new RectF(415, 43, 547, 63);
                                        Paint translucentBadgeBg = new Paint();
                                        translucentBadgeBg.setColor(Color.argb(65, 255, 255, 255));
                                        canvas.drawRoundRect(invBadge, 5, 5, translucentBadgeBg);

                                        Paint invBadgeText = new Paint(thTextPaint);
                                        invBadgeText.setTextSize(9.5f);
                                        canvas.drawText(headingText, 426, 57, invBadgeText);

                                        Paint whiteInvNum = new Paint();
                                        whiteInvNum.setColor(Color.WHITE);
                                        whiteInvNum.setTextSize(9.5f);
                                        whiteInvNum.setFakeBoldText(true);
                                        whiteInvNum.setAntiAlias(true);

                                        canvas.drawText("#" + invoiceNumber, 426, 76, whiteInvNum);
                                        canvas.drawText(dateStr, 426, 89, whiteSubPaint);

                                        // 2. Billed To Card (Matching preview)
                                        RectF custBanner = new RectF(36, 110, 559, 134);
                                        canvas.drawRoundRect(custBanner, 6, 6, badgeBg);
                                        canvas.drawRoundRect(custBanner, 6, 6, linePaint);

                                        String custStr = "BILLED TO: " + customerName;
                                        if (customerPhone != null && !customerPhone.trim().isEmpty()) {
                                            custStr += "  •  Mob: " + customerPhone;
                                        }
                                        if (doctorName != null && !doctorName.trim().isEmpty()) {
                                            custStr += "  •  Dr: " + doctorName;
                                        }
                                        if (tableNumber != null && !tableNumber.trim().isEmpty()) {
                                            custStr += "  •  Table: " + tableNumber;
                                        }
                                        canvas.drawText(custStr, 46, 126, boldTextPaint);

                                        // Paid status badge
                                        String paidText = "PAID (" + paymentMode.toUpperCase() + ")";
                                        RectF paidBadge = new RectF(455, 115, 550, 129);
                                        Paint paidBgPaint = new Paint();
                                        paidBgPaint.setColor(Color.rgb(236, 253, 245));
                                        canvas.drawRoundRect(paidBadge, 4, 4, paidBgPaint);
                                        Paint paidTextPaint = new Paint();
                                        paidTextPaint.setColor(Color.rgb(5, 150, 105));
                                        paidTextPaint.setTextSize(8.5f);
                                        paidTextPaint.setFakeBoldText(true);
                                        paidTextPaint.setAntiAlias(true);
                                        canvas.drawText(paidText, 465, 125.5f, paidTextPaint);

                                        // 3. Table Header Bar (Themed)
                                        RectF thRect = new RectF(36, 142, 559, 164);
                                        canvas.drawRoundRect(thRect, 6, 6, thBgPaint);
                                        canvas.drawText("S.NO", 44, 156, thTextPaint);
                                        canvas.drawText("ITEM DESCRIPTION", 80, 156, thTextPaint);
                                        canvas.drawText("QTY", 370, 156, thTextPaint);
                                        canvas.drawText("UNIT RATE", 435, 156, thTextPaint);
                                        canvas.drawText("AMOUNT (₹)", 495, 156, thTextPaint);

                                        currentY = 184;
                                    } else {
                                        // --- CONTINUATION PAGES (PAGE 2+) ---
                                        canvas.drawText(storeName.toUpperCase(), 36, 48, darkPaint);
                                        canvas.drawText(headingText + " (Continued - Page " + pageIdx + " of " + totalPages + ")", 230, 48, subPaint);
                                        canvas.drawText("#" + invoiceNumber, 450, 48, boldTextPaint);

                                        canvas.drawLine(36, 56, 559, 56, linePaint);

                                        // Table Header identical to page 1
                                        RectF thRect = new RectF(36, 64, 559, 86);
                                        canvas.drawRoundRect(thRect, 6, 6, thBgPaint);
                                        canvas.drawText("S.NO", 44, 78, thTextPaint);
                                        canvas.drawText("ITEM DESCRIPTION", 80, 78, thTextPaint);
                                        canvas.drawText("QTY", 370, 78, thTextPaint);
                                        canvas.drawText("UNIT RATE", 435, 78, thTextPaint);
                                        canvas.drawText("AMOUNT (₹)", 495, 78, thTextPaint);

                                        currentY = 106;
                                    }

                                    // Render Items for this page
                                    List<Map<String, Object>> pageItems = pagesItems.get(pageIdx - 1);
                                    for (Map<String, Object> item : pageItems) {
                                        String name = String.valueOf(item.get("name"));
                                        String qty = String.valueOf(item.get("qty"));
                                        String rate = String.valueOf(item.get("rate"));
                                        String amt = String.valueOf(item.get("amount"));

                                        canvas.drawText(String.valueOf(globalSNo++), 48, currentY, subPaint);
                                        if (name.length() > 44) name = name.substring(0, 42) + "...";
                                        canvas.drawText(name, 80, currentY, itemNamePaint);
                                        canvas.drawText(qty, 375, currentY, bodyPaint);
                                        canvas.drawText(rate, 440, currentY, bodyPaint);
                                        canvas.drawText(amt, 498, currentY, boldTextPaint);

                                        canvas.drawLine(36, currentY + 6, 559, currentY + 6, rowLinePaint);
                                        currentY += 24;
                                    }

                                    // If last page, render Summary, Terms & Signatory Block
                                    if (pageIdx == totalPages) {
                                        canvas.drawLine(36, currentY + 2, 559, currentY + 2, linePaint);
                                        currentY += 12;

                                        // Left: Dynamic UPI QR / Payment Box (Matching live preview)
                                        if (showDynamicUpiQr && !upiId.trim().isEmpty()) {
                                            RectF upiBox = new RectF(36, currentY, 210, currentY + 52);
                                            canvas.drawRoundRect(upiBox, 6, 6, badgeBg);
                                            canvas.drawRoundRect(upiBox, 6, 6, linePaint);

                                            Paint upiTitlePaint = new Paint(boldTextPaint);
                                            upiTitlePaint.setTextSize(9f);
                                            canvas.drawText("Primary Shop QR (Instant UPI)", 44, currentY + 16, upiTitlePaint);

                                            Paint upiIdPaint = new Paint(subPaint);
                                            upiIdPaint.setTextSize(8.5f);
                                            canvas.drawText(upiId, 44, currentY + 30, upiIdPaint);

                                            Paint upiFree = new Paint(subPaint);
                                            upiFree.setColor(Color.rgb(16, 185, 129));
                                            upiFree.setTextSize(7.5f);
                                            upiFree.setFakeBoldText(true);
                                            canvas.drawText("Zero transaction charges • Verified", 44, currentY + 44, upiFree);
                                        }

                                        // Terms & Conditions block
                                        float termsX = showDynamicUpiQr ? 220 : 36;
                                        canvas.drawText("Terms & Conditions:", termsX, currentY + 12, boldTextPaint);
                                        String[] termLines = termsText.split("\n");
                                        float tY = currentY + 24;
                                        for (int tl = 0; tl < termLines.length && tl < 3; tl++) {
                                            String line = termLines[tl];
                                            if (line.length() > 36) line = line.substring(0, 36) + "...";
                                            canvas.drawText(line, termsX, tY, subPaint);
                                            tY += 11;
                                        }

                                        // Right: Totals Box
                                        int totalsX = 380;
                                        int totalsY = currentY;
                                        if (discountAmount != null && !discountAmount.isEmpty() && !discountAmount.equals("₹0.00") && !discountAmount.equals("0")) {
                                            canvas.drawText("Subtotal:", totalsX, totalsY, subPaint);
                                            canvas.drawText(subtotalAmount, 490, totalsY, bodyPaint);
                                            totalsY += 12;
                                            canvas.drawText("Discount:", totalsX, totalsY, subPaint);
                                            canvas.drawText("-" + discountAmount, 490, totalsY, bodyPaint);
                                            totalsY += 12;
                                        }
                                        if (taxAmount != null && !taxAmount.isEmpty() && !taxAmount.equals("₹0.00") && !taxAmount.equals("0")) {
                                            canvas.drawText("GST Tax:", totalsX, totalsY, subPaint);
                                            canvas.drawText(taxAmount, 490, totalsY, bodyPaint);
                                            totalsY += 12;
                                        }

                                        // Grand Total Pill (Theme Colored)
                                        RectF gtBox = new RectF(370, totalsY + 4, 559, totalsY + 36);
                                        canvas.drawRoundRect(gtBox, 6, 6, grandTotalBg);

                                        Paint gtLabel = new Paint(thTextPaint);
                                        gtLabel.setTextSize(9.5f);
                                        canvas.drawText("GRAND TOTAL", 380, totalsY + 24, gtLabel);

                                        Paint gtVal = new Paint();
                                        gtVal.setColor(Color.WHITE);
                                        gtVal.setTextSize(13.5f);
                                        gtVal.setFakeBoldText(true);
                                        gtVal.setAntiAlias(true);
                                        canvas.drawText(totalAmount, 475, totalsY + 24, gtVal);

                                        // Branding / Thank You Footer Strip
                                        if (!isPro) {
                                            // Free Tier: Professional KamaiPlus Branding Card with increased height (34pt)
                                            float promoY = totalsY + 44;
                                            RectF promoStrip = new RectF(36, promoY, 559, promoY + 34);
                                            canvas.drawRoundRect(promoStrip, 8, 8, thBgPaint);

                                            Paint promoTextTitle = new Paint();
                                            promoTextTitle.setColor(Color.WHITE);
                                            promoTextTitle.setTextSize(9.5f);
                                            promoTextTitle.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                                            promoTextTitle.setAntiAlias(true);

                                            Paint promoTextSub = new Paint();
                                            promoTextSub.setColor(Color.argb(230, 255, 255, 255));
                                            promoTextSub.setTextSize(7.5f);
                                            promoTextSub.setAntiAlias(true);

                                            canvas.drawText("⚡ POWERED BY KAMAIPLUS  •  INDIA'S #1 RETAIL POS & BILLING APP", 48, promoY + 14, promoTextTitle);
                                            canvas.drawText("Billing, GST Invoicing, Khata Ledger & Inventory Management  •  www.kamaiplus.com", 48, promoY + 26, promoTextSub);
                                        } else {
                                            // Pro Tier: 100% White-Label (No marketing promo banner!)
                                            if (footerNote != null && !footerNote.trim().isEmpty()) {
                                                float noteY = totalsY + 44;
                                                Paint proFooterNote = new Paint(subPaint);
                                                proFooterNote.setTextSize(8.5f);
                                                proFooterNote.setColor(Color.rgb(71, 85, 105));
                                                canvas.drawText(footerNote, 36, noteY + 14, proFooterNote);
                                            }
                                        }
                                    }

                                    // --- FOOTER ON EVERY PAGE ---
                                    canvas.drawLine(36, 810, 559, 810, linePaint);
                                    String footerBranding = isPro ? "Printed via KamaiPlus" : "Powered by KamaiPlus • Retail & Inventory Software";
                                    canvas.drawText(footerBranding, 36, 822, subPaint);
                                    canvas.drawText("Page " + pageIdx + " of " + totalPages, 505, 822, boldTextPaint);

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
                                            shareIntent.putExtra(Intent.EXTRA_TEXT, "Namaste! Here is your document #" + invNum + " from " + sName + ".");
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

    @Override
    protected void onDestroy() {
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
        super.onDestroy();
    }
}
