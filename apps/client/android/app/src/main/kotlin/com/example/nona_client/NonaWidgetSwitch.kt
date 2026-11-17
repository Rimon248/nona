package com.example.nona_client

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface

/** Exact proportions of the selected widget toggle, independent of launcher themes. */
internal object NonaWidgetSwitch {
    private const val coral = 0xFFE36B55.toInt()
    private const val green = 0xFF3C9A72.toInt()
    private const val grey = 0xFF7F8991.toInt()
    private const val cream = 0xFFFBF0D9.toInt()

    fun bitmap(context: Context, progress: Float, connecting: Boolean, scale: Float = 1f): Bitmap {
        val density = context.resources.displayMetrics.density * scale
        val width = (64 * density).toInt().coerceAtLeast(64)
        val height = (48 * density).toInt().coerceAtLeast(48)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(density, density)
        val value = progress.coerceIn(0f, 1f)
        val eased = value * value * (3f - 2f * value)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = if (connecting) grey else Color.rgb(
            (Color.red(coral) + (Color.red(green) - Color.red(coral)) * eased).toInt(),
            (Color.green(coral) + (Color.green(green) - Color.green(coral)) * eased).toInt(),
            (Color.blue(coral) + (Color.blue(green) - Color.blue(coral)) * eased).toInt(),
        )
        canvas.drawRoundRect(RectF(4f, 10f, 60f, 38f), 14f, 14f, paint)
        paint.color = cream
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = 8f
        paint.alpha = if (connecting) 0 else (255 * eased).toInt()
        canvas.drawText("ВКЛ", 18f, 27f, paint)
        paint.textSize = 7f
        paint.alpha = if (connecting) 0 else (255 * (1f - eased)).toInt()
        canvas.drawText("ВЫКЛ", 46f, 26.5f, paint)
        paint.alpha = 255
        if (connecting) {
            paint.textSize = 9f
            canvas.drawText("…", 18f, 27f, paint)
        }
        paint.color = cream
        canvas.drawCircle(18f + 28f * eased, 24f, 12f, paint)
        return bitmap
    }
}
