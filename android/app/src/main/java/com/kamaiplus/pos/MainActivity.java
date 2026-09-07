package com.kamaiplus.pos;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
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

        // 4. Native PDF Generation & Download Engine
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PDF_CHANNEL)
                .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                    @Override
                    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
                        if ("generateAndSaveInvoicePdf".equals(call.method)) {
                            try {
                                String invoiceNumber = call.argument("invoiceNumber");
                                String storeName = call.argument("storeName");
                                String customerName = call.argument("customerName");
                                String dateStr = call.argument("dateStr");
                                String paymentMode = call.argument("paymentMode");
                                String totalAmount = call.argument("totalAmount");
                                List<Map<String, Object>> items = call.argument("items");

                                if (invoiceNumber == null) invoiceNumber = "INV_" + System.currentTimeMillis();
                                if (storeName == null) storeName = "KamaiPlus Store";
                                if (customerName == null) customerName = "Walk-in Customer";
                                if (dateStr == null) dateStr = "";
                                if (paymentMode == null) paymentMode = "CASH";
                                if (totalAmount == null) totalAmount = "₹0.00";
                                if (items == null) items = new ArrayList<>();

                                // Generate standard A4 (595 x 842 points)
                                PdfDocument document = new PdfDocument();
                                PdfDocument.PageInfo pageInfo = new PdfDocument.PageInfo.Builder(595, 842, 1).create();
                                PdfDocument.Page page = document.startPage(pageInfo);
                                Canvas canvas = page.getCanvas();

                                Paint titlePaint = new Paint();
                                titlePaint.setColor(Color.rgb(15, 23, 42)); // Slate 900
                                titlePaint.setTextSize(20);
                                titlePaint.setFakeBoldText(true);

                                Paint subPaint = new Paint();
                                subPaint.setColor(Color.rgb(100, 116, 139)); // Slate 500
                                subPaint.setTextSize(11);

                                Paint boldPaint = new Paint();
                                boldPaint.setColor(Color.rgb(15, 23, 42));
                                boldPaint.setTextSize(11);
                                boldPaint.setFakeBoldText(true);

                                Paint linePaint = new Paint();
                                linePaint.setColor(Color.rgb(226, 232, 240));
                                linePaint.setStrokeWidth(1f);

                                // Header
                                canvas.drawText(storeName.toUpperCase(), 40, 50, titlePaint);
                                canvas.drawText("TAX INVOICE / CASH MEMO", 40, 68, subPaint);
                                canvas.drawText("Original for Recipient", 400, 50, subPaint);
                                canvas.drawText("Invoice #: " + invoiceNumber, 400, 68, boldPaint);

                                canvas.drawLine(40, 80, 555, 80, linePaint);

                                // Customer & Bill Meta
                                canvas.drawText("Billed To: " + customerName, 40, 100, boldPaint);
                                canvas.drawText("Date: " + dateStr, 400, 100, subPaint);
                                canvas.drawText("Payment Mode: " + paymentMode.toUpperCase(), 400, 116, boldPaint);

                                canvas.drawLine(40, 128, 555, 128, linePaint);

                                // Table Header
                                Paint thBg = new Paint();
                                thBg.setColor(Color.rgb(241, 245, 249));
                                canvas.drawRect(40, 134, 555, 154, thBg);

                                canvas.drawText("S.NO", 48, 148, boldPaint);
                                canvas.drawText("ITEM DESCRIPTION", 100, 148, boldPaint);
                                canvas.drawText("QTY", 370, 148, boldPaint);
                                canvas.drawText("RATE", 430, 148, boldPaint);
                                canvas.drawText("AMOUNT", 495, 148, boldPaint);

                                int y = 174;
                                int sNo = 1;
                                for (Map<String, Object> item : items) {
                                    if (y > 760) break; // stay within page
                                    String name = String.valueOf(item.get("name"));
                                    String qty = String.valueOf(item.get("qty"));
                                    String rate = String.valueOf(item.get("rate"));
                                    String amt = String.valueOf(item.get("amount"));

                                    canvas.drawText(String.valueOf(sNo++), 48, y, subPaint);
                                    if (name.length() > 32) name = name.substring(0, 32) + "...";
                                    canvas.drawText(name, 100, y, boldPaint);
                                    canvas.drawText(qty, 375, y, subPaint);
                                    canvas.drawText(rate, 430, y, subPaint);
                                    canvas.drawText(amt, 495, y, boldPaint);

                                    y += 20;
                                }

                                canvas.drawLine(40, y + 5, 555, y + 5, linePaint);
                                y += 26;

                                // Grand Total
                                Paint totalBg = new Paint();
                                totalBg.setColor(Color.rgb(254, 243, 199)); // Light Amber
                                canvas.drawRect(350, y - 16, 555, y + 16, totalBg);

                                canvas.drawText("GRAND TOTAL:", 360, y + 4, boldPaint);
                                Paint amtPaint = new Paint();
                                amtPaint.setColor(Color.rgb(15, 23, 42));
                                amtPaint.setTextSize(14);
                                amtPaint.setFakeBoldText(true);
                                canvas.drawText(totalAmount, 460, y + 4, amtPaint);

                                // Footer
                                canvas.drawText("Thank you for your business! Terms: Goods once sold cannot be taken back.", 40, 800, subPaint);
                                canvas.drawText("Generated electronically via Kamai+ POS", 380, 800, subPaint);

                                document.finishPage(page);

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
                                        .setContentTitle("Invoice PDF Downloaded 📥")
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
