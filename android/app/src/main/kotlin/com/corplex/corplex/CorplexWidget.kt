package com.corplex.corplex

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Reads what Dart wrote through home_widget ("title", "detail", "uri") and
// shows it; taps launch MainActivity with a corplex:// link.
class CorplexWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.corplex_widget)
            views.setOnClickPendingIntent(
                R.id.widget_new_note,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("corplex://new-note")),
            )
            val title = widgetData.getString("title", null)
            val uri = widgetData.getString("uri", null)
            if (title.isNullOrEmpty()) {
                views.setViewVisibility(R.id.widget_continue, View.GONE)
            } else {
                val detail = widgetData.getString("detail", "") ?: ""
                views.setViewVisibility(R.id.widget_continue, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_title, if (detail.isEmpty()) title else "$title · $detail")
                if (uri != null) {
                    views.setOnClickPendingIntent(
                        R.id.widget_continue,
                        HomeWidgetLaunchIntent.getActivity(
                            context, MainActivity::class.java, Uri.parse(uri)),
                    )
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
