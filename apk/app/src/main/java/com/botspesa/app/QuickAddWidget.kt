package com.botspesa.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class QuickAddWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val intent = Intent(context, QuickAddActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
        val label = context.getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
            .getString("widget_dest_label", null)
        views.setTextViewText(
            R.id.widget_label,
            if (label == null || label == "Lista Personale") "Aggiungi alla spesa…" else "Aggiungi a $label…"
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}
