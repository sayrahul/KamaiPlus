package com.kamaiplus.pos.widget;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.widget.RemoteViews;
import com.kamaiplus.pos.MainActivity;
import com.kamaiplus.pos.R;

public class QuickPosWidgetProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_quick_pos);

            // 1-Tap -> Direct to POS Counter screen
            Intent posIntent = new Intent(context, MainActivity.class);
            posIntent.setAction(Intent.ACTION_VIEW);
            posIntent.setData(Uri.parse("kamaiplus://shortcut/pos"));
            posIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            posIntent.putExtra("shortcut", "pos");
            posIntent.putExtra("test_screen", "pos");
            PendingIntent pendingPos = PendingIntent.getActivity(
                context, 3001, posIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            views.setOnClickPendingIntent(R.id.widget_quick_pos_container, pendingPos);

            appWidgetManager.updateAppWidget(appWidgetId, views);
        }
    }
}
