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
        views.setOnClickPendingIntent(R.id.widget_bar, pending)
        val prefs = context.getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
        val apri = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("ctx_gruppo", prefs.getInt("widget_dest_gruppo", 0))
            .putExtra("ctx_topic", prefs.getInt("widget_dest_topic", 0))
        // FLAG_UPDATE_CURRENT: gli extra vengono aggiornati a ogni refresh del widget
        val pendingApri = PendingIntent.getActivity(
            context, 1, apri,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_apri_app, pendingApri)
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}
