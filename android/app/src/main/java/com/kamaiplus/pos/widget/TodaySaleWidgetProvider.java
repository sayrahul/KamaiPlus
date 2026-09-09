package com.kamaiplus.pos.widget;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.widget.RemoteViews;
import com.kamaiplus.pos.MainActivity;
import com.kamaiplus.pos.R;

public class TodaySaleWidgetProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        updateWidgets(context, appWidgetManager, appWidgetIds);
    }

    public static void updateWidgets(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        SharedPreferences sp = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE);
        
        String todaySale = sp.getString("today_sale", "₹0");
        String khataDue = sp.getString("khata_due", "₹0");
        String cashInHand = sp.getString("cash_in_hand", "₹0");
        String storeName = sp.getString("store_name", "KamaiPlus Store");

        for (int appWidgetId : appWidgetIds) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_today_sale);
            views.setTextViewText(R.id.tv_widget_store_name, storeName);
            views.setTextViewText(R.id.tv_widget_today_sale, todaySale);
            views.setTextViewText(R.id.tv_widget_khata_due, khataDue);
            views.setTextViewText(R.id.tv_widget_cash_in_hand, cashInHand);

            // Action: New Bill Button -> Opens POS counter directly
            Intent posIntent = new Intent(context, MainActivity.class);
            posIntent.setAction(Intent.ACTION_VIEW);
            posIntent.setData(Uri.parse("kamaiplus://shortcut/pos"));
            posIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            posIntent.putExtra("shortcut", "pos");
            posIntent.putExtra("test_screen", "pos");
            PendingIntent pendingPos = PendingIntent.getActivity(
                context, 2001, posIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            views.setOnClickPendingIntent(R.id.btn_widget_new_bill, pendingPos);

            // Action: Tap Card -> Opens Dashboard
            Intent openIntent = new Intent(context, MainActivity.class);
            openIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pendingOpen = PendingIntent.getActivity(
                context, 2002, openIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            views.setOnClickPendingIntent(R.id.widget_container, pendingOpen);

            appWidgetManager.updateAppWidget(appWidgetId, views);
        }
    }
}
