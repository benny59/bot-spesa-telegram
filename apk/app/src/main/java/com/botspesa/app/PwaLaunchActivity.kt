package com.botspesa.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

/** Apre la PWA dall'icona del widget. Al primo uso chiede l'indirizzo (modificabile da Configurazione rete). */
class PwaLaunchActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
        val url = prefs.getString("pwa_url", "").orEmpty().trim()
        if (url.startsWith("http")) {
            apri(url)
            return
        }
        val input = EditText(this).apply {
            hint = "https://nome.duckdns.org:4443/app/"
            setText("https://")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
        }
        AlertDialog.Builder(this)
            .setTitle("Indirizzo della PWA")
            .setView(input)
            .setPositiveButton("Salva e apri") { _, _ ->
                val nuovo = input.text.toString().trim()
                if (nuovo.startsWith("http")) {
                    prefs.edit().putString("pwa_url", nuovo).apply()
                    apri(nuovo)
                } else finish()
            }
            .setNegativeButton("Annulla") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun apri(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            Toast.makeText(this, "Impossibile aprire $url", Toast.LENGTH_LONG).show()
        }
        finish()
    }
}
