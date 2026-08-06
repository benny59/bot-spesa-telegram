package com.botspesa.app

import android.os.Bundle
import android.view.View
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import coil.load

class FotoActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_ITEM_ID = "extra_item_id"
        const val EXTRA_NOME    = "extra_nome"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_foto)

        window.attributes = window.attributes.also { it.screenBrightness = 1.0f }

        val itemId   = intent.getIntExtra(EXTRA_ITEM_ID, 0)
        val nome     = intent.getStringExtra(EXTRA_NOME) ?: ""
        val progress = findViewById<ProgressBar>(R.id.progressFoto)
        val imgView  = findViewById<ImageView>(R.id.imgFoto)

        findViewById<TextView>(R.id.tvNomeFoto).text = nome

        imgView.load(ApiClient.getFotoUrl(itemId), ApiClient.imageLoader(this)) {
            listener(
                onStart   = { progress.visibility = View.VISIBLE },
                onSuccess = { _, _ -> progress.visibility = View.GONE },
                onError   = { _, _ -> progress.visibility = View.GONE }
            )
        }

        findViewById<View>(R.id.btnChiudiFoto).setOnClickListener { finish() }
    }
}
