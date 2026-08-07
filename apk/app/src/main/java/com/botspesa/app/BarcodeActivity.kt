package com.botspesa.app

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter

class BarcodeActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_NOME    = "extra_nome"
        const val EXTRA_CODICE  = "extra_codice"
        const val EXTRA_FORMATO = "extra_formato"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_barcode)

        // Massima luminosità per facilità di lettura scanner
        window.attributes = window.attributes.also { it.screenBrightness = 1.0f }

        val nome    = intent.getStringExtra(EXTRA_NOME) ?: ""
        val codice  = intent.getStringExtra(EXTRA_CODICE) ?: ""
        val formato = intent.getStringExtra(EXTRA_FORMATO) ?: "qrcode"

        findViewById<TextView>(R.id.tvNomeCarta).text = nome
        findViewById<TextView>(R.id.tvCodiceCarta).text = codice

        generaBarcode(codice, formato)?.let {
            findViewById<ImageView>(R.id.imgBarcode).setImageBitmap(it)
        }

        findViewById<android.view.View>(R.id.btnChiudi).setOnClickListener { finish() }
    }

    private fun generaBarcode(codice: String, formato: String): Bitmap? = runCatching {
        val fmt = when (formato.lowercase()) {
            "ean13"         -> BarcodeFormat.EAN_13
            "ean8"          -> BarcodeFormat.EAN_8
            "code39"        -> BarcodeFormat.CODE_39
            "code128"       -> BarcodeFormat.CODE_128
            "itf", "code25" -> BarcodeFormat.ITF
            else            -> BarcodeFormat.QR_CODE
        }
        val isLinear = fmt != BarcodeFormat.QR_CODE
        val w = if (isLinear) 900 else 600
        val h = if (isLinear) 280 else 600
        val matrix = MultiFormatWriter().encode(codice, fmt, w, h, mapOf(EncodeHintType.MARGIN to 1))
        Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565).also { bmp ->
            for (x in 0 until w) for (y in 0 until h)
                bmp.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
        }
    }.getOrNull()
}
