package com.kamaiplus.pos;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.speech.tts.TextToSpeech;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.content.FileProvider;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public class MainActivity extends FlutterActivity implements TextToSpeech.OnInitListener {
    private static final String SOUNDBOX_CHANNEL = "com.kamaiplus.pos/soundbox";
    private static final String BT_CHANNEL = "com.kamaiplus.pos/bluetooth_printer";
    private static final String NOTIFICATION_CHANNEL = "com.kamaiplus.pos/notifications";
    private static final String PDF_CHANNEL = "com.kamaiplus.pos/pdf_engine";
    private static final String CHANNEL_ID = "kamai_pos_channel";
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");

    private TextToSpeech tts;
    private boolean isTtsReady = false;

    @Override
    protected void onResume() {
        super.onResume();
        handleTestIntent(getIntent());
    }

    @Override
    protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        handleTestIntent(intent);
    }

    private void handleTestIntent(android.content.Intent intent) {
        if (intent != null && intent.hasExtra("test_screen")) {
            String testScreen = intent.getStringExtra("test_screen");
            android.content.SharedPreferences sp = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE);
            sp.edit().putString("flutter.test_screen", testScreen).commit();
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

        // 1. TextToSpeech Voice Engine
        tts = new TextToSpeech(this, this);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SOUNDBOX_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("speak".equals(call.method)) {
                            String text = call.argument("text");
                            String language = call.argument("lang");
                            if (isTtsReady && text != null && !text.isEmpty()) {
                                Locale locale = "hi".equals(language) ? new Locale("hi", "IN") : new Locale("en", "IN");
                                tts.setLanguage(locale);
                                tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "KAMAI_TTS");
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

                                if (invoiceNumber == null) invoiceNumber = "INV-" + System.currentTimeMillis();
                                if (storeName == null || storeName.trim().isEmpty()) storeName = "KamaiPlus Store";
                                if (customerName == null || customerName.trim().isEmpty()) customerName = "Cash Customer";
                                if (dateStr == null) dateStr = "";
                                if (paymentMode == null) paymentMode = "CASH";
                                if (totalAmount == null) totalAmount = "₹0.00";
                                if (subtotalAmount == null) subtotalAmount = totalAmount;
                                if (items == null) items = new ArrayList<>();

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
                                boldTextPaint.setFakeBoldText(true);
                                boldTextPaint.setAntiAlias(true);

                                Paint linePaint = new Paint();
                                linePaint.setColor(Color.rgb(226, 232, 240)); // Slate 200
                                linePaint.setStrokeWidth(0.8f);

                                Paint rowLinePaint = new Paint();
                                rowLinePaint.setColor(Color.rgb(241, 245, 249)); // Slate 100
                                rowLinePaint.setStrokeWidth(0.6f);

                                Paint thBgPaint = new Paint();
                                thBgPaint.setColor(Color.rgb(15, 23, 42)); // Dark Slate Header

                                Paint thTextPaint = new Paint();
                                thTextPaint.setColor(Color.WHITE);
                                thTextPaint.setTextSize(9f);
                                thTextPaint.setFakeBoldText(true);
                                thTextPaint.setAntiAlias(true);

                                Paint badgeBg = new Paint();
                                badgeBg.setColor(Color.rgb(241, 245, 249));

                                Paint grandTotalBg = new Paint();
                                grandTotalBg.setColor(Color.rgb(15, 23, 42));

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
                                // Page 1 items capacity: y from 172 to 740 is 568pt.
                                // With totals (90pt space), capacity is (568 - 90)/20 = 23 items.
                                // Subsequent pages capacity: y from 104 to 740 is 636pt.
                                // Capacity with totals is (636 - 90)/20 = 27 items. Without totals = 31 items.
                                List<List<Map<String, Object>>> pagesItems = new ArrayList<>();
                                int itemIndex = 0;
                                int totalItems = items.size();

                                // Page 1 items
                                List<Map<String, Object>> p1Items = new ArrayList<>();
                                int p1Limit = (totalItems <= 23) ? totalItems : 27;
                                for (int i = 0; i < p1Limit && itemIndex < totalItems; i++) {
                                    p1Items.add(items.get(itemIndex++));
                                }
                                pagesItems.add(p1Items);

                                // Subsequent pages
                                while (itemIndex < totalItems) {
                                    List<Map<String, Object>> nextP = new ArrayList<>();
                                    int remaining = totalItems - itemIndex;
                                    int nextLimit = (remaining <= 27) ? remaining : 31;
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
                                        // --- PAGE 1 FULL HEADER ---
                                        float textLeft = 36;
                                        if (logoBmp != null) {
                                            RectF logoRect = new RectF(36, 36, 86, 86);
                                            Paint bmpPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
                                            canvas.drawBitmap(logoBmp, null, logoRect, bmpPaint);
                                            textLeft = 96;
                                        }

                                        // Store Details
                                        canvas.drawText(storeName.toUpperCase(), textLeft, 52, darkPaint);
                                        float storeSubY = 66;
                                        if (storeAddress != null && !storeAddress.trim().isEmpty()) {
                                            String addr = storeAddress.length() > 40 ? storeAddress.substring(0, 40) + "..." : storeAddress;
                                            canvas.drawText(addr, textLeft, storeSubY, subPaint);
                                            storeSubY += 12;
                                        }
                                        String contactInfo = "";
                                        if (storePhone != null && !storePhone.trim().isEmpty()) contactInfo += "Ph: " + storePhone + "  ";
                                        if (gstin != null && !gstin.trim().isEmpty()) contactInfo += "GSTIN: " + gstin;
                                        if (!contactInfo.isEmpty()) {
                                            canvas.drawText(contactInfo, textLeft, storeSubY, subPaint);
                                        }

                                        // Top Right Header Card
                                        RectF invBadge = new RectF(405, 36, 559, 56);
                                        canvas.drawRoundRect(invBadge, 4, 4, thBgPaint);
                                        Paint invBadgeText = new Paint(thTextPaint);
                                        invBadgeText.setTextSize(10f);
                                        canvas.drawText("TAX INVOICE", 448, 50, invBadgeText);

                                        canvas.drawText("Invoice #: " + invoiceNumber, 410, 70, boldTextPaint);
                                        canvas.drawText("Date: " + dateStr, 410, 83, subPaint);
                                        canvas.drawText("Payment: " + paymentMode.toUpperCase(), 410, 96, boldTextPaint);

                                        // Divider
                                        canvas.drawLine(36, 104, 559, 104, linePaint);

                                        // Customer Banner
                                        RectF custBanner = new RectF(36, 110, 559, 134);
                                        canvas.drawRoundRect(custBanner, 4, 4, badgeBg);
                                        canvas.drawRoundRect(custBanner, 4, 4, linePaint);

                                        String custStr = "Billed To: " + customerName;
                                        if (customerPhone != null && !customerPhone.trim().isEmpty()) {
                                            custStr += "  •  Mobile: " + customerPhone;
                                        }
                                        canvas.drawText(custStr, 46, 126, boldTextPaint);
                                        canvas.drawText("Supply: Local State (Intrastate)", 405, 126, subPaint);

                                        // Table Header
                                        RectF thRect = new RectF(36, 142, 559, 164);
                                        canvas.drawRoundRect(thRect, 4, 4, thBgPaint);
                                        canvas.drawText("S.NO", 44, 156, thTextPaint);
                                        canvas.drawText("ITEM DESCRIPTION", 80, 156, thTextPaint);
                                        canvas.drawText("QTY", 370, 156, thTextPaint);
                                        canvas.drawText("UNIT RATE", 435, 156, thTextPaint);
                                        canvas.drawText("AMOUNT (₹)", 495, 156, thTextPaint);

                                        currentY = 184;
                                    } else {
                                        // --- CONTINUATION PAGES (PAGE 2+) ---
                                        canvas.drawText(storeName.toUpperCase(), 36, 48, darkPaint);
                                        canvas.drawText("TAX INVOICE (Continued - Page " + pageIdx + " of " + totalPages + ")", 230, 48, subPaint);
                                        canvas.drawText("Invoice #: " + invoiceNumber, 430, 48, boldTextPaint);

                                        canvas.drawLine(36, 56, 559, 56, linePaint);

                                        // Table Header identical to page 1
                                        RectF thRect = new RectF(36, 64, 559, 86);
                                        canvas.drawRoundRect(thRect, 4, 4, thBgPaint);
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
                                        if (name.length() > 36) name = name.substring(0, 36) + "...";
                                        canvas.drawText(name, 80, currentY, boldTextPaint);
                                        canvas.drawText(qty, 375, currentY, bodyPaint);
                                        canvas.drawText(rate, 440, currentY, bodyPaint);
                                        canvas.drawText(amt, 500, currentY, boldTextPaint);

                                        canvas.drawLine(36, currentY + 4, 559, currentY + 4, rowLinePaint);
                                        currentY += 19;
                                    }

                                    // If last page, render Summary and Signatory Block
                                    if (pageIdx == totalPages) {
                                        canvas.drawLine(36, currentY + 2, 559, currentY + 2, linePaint);
                                        currentY += 14;

                                        // Left: Terms & Signatory
                                        canvas.drawText("Terms & Conditions:", 36, currentY, boldTextPaint);
                                        canvas.drawText("1. Goods once sold cannot be taken back or exchanged.", 36, currentY + 12, subPaint);
                                        canvas.drawText("2. Electronic invoice generated via Kamai+ POS System.", 36, currentY + 24, subPaint);

                                        // Signatory Box
                                        RectF signBox = new RectF(220, currentY + 2, 335, currentY + 54);
                                        canvas.drawRoundRect(signBox, 4, 4, badgeBg);
                                        canvas.drawRoundRect(signBox, 4, 4, linePaint);
                                        canvas.drawText("For " + (storeName.length() > 18 ? storeName.substring(0, 18) : storeName), 226, currentY + 14, subPaint);
                                        canvas.drawText("Authorized Signatory", 226, currentY + 46, boldTextPaint);

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

                                        // Grand Total Pill
                                        RectF gtBox = new RectF(370, totalsY + 4, 559, totalsY + 36);
                                        canvas.drawRoundRect(gtBox, 6, 6, grandTotalBg);

                                        Paint gtLabel = new Paint(thTextPaint);
                                        gtLabel.setTextSize(10f);
                                        canvas.drawText("TOTAL DUE", 382, totalsY + 24, gtLabel);

                                        Paint gtVal = new Paint();
                                        gtVal.setColor(Color.WHITE);
                                        gtVal.setTextSize(14f);
                                        gtVal.setFakeBoldText(true);
                                        gtVal.setAntiAlias(true);
                                        canvas.drawText(totalAmount, 480, totalsY + 24, gtVal);
                                    }

                                    // --- FOOTER ON EVERY PAGE ---
                                    canvas.drawLine(36, 810, 559, 810, linePaint);
                                    canvas.drawText("Kamai+ POS • Retail & Inventory Software", 36, 822, subPaint);
                                    canvas.drawText("Page " + pageIdx + " of " + totalPages, 505, 822, boldTextPaint);

                                    document.finishPage(page);
                                }

                                // Save PDF to Downloads directory
                                File downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                                if (!downloadsDir.exists()) downloadsDir.mkdirs();

                                String cleanInv = invoiceNumber.replaceAll("[^a-zA-Z0-9_-]", "_");
                                File pdfFile = new File(downloadsDir, "Kamai_Invoice_" + cleanInv + ".pdf");
                                FileOutputStream fos = new FileOutputStream(pdfFile);
                                document.writeTo(fos);
                                fos.close();
                                document.close();

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
                        } else if ("openPdf".equals(call.method)) {
                            try {
                                String path = call.argument("path");
                                if (path != null) {
                                    File file = new File(path);
                                    if (file.exists()) {
                                        Intent intent = new Intent(Intent.ACTION_VIEW);
                                        Uri uri = FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", file);
                                        intent.setDataAndType(uri, "application/pdf");
                                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
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
                                if (invNum == null) invNum = "BILL";
                                if (sName == null) sName = "KamaiPlus";

                                if (path != null) {
                                    File file = new File(path);
                                    if (file.exists()) {
                                        Uri uri = FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", file);
                                        Intent shareIntent = new Intent(Intent.ACTION_SEND);
                                        shareIntent.setType("application/pdf");
                                        shareIntent.putExtra(Intent.EXTRA_STREAM, uri);
                                        shareIntent.putExtra(Intent.EXTRA_SUBJECT, "Tax Invoice #" + invNum + " - " + sName);
                                        shareIntent.putExtra(Intent.EXTRA_TEXT, "Namaste! Here is your Tax Invoice #" + invNum + " from " + sName + ".");
                                        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

                                        Intent chooser = Intent.createChooser(shareIntent, "Share Tax Invoice PDF via...");
                                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
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
