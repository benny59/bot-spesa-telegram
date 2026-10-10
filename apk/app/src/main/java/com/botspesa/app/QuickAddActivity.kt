package com.botspesa.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Mini-finestra aperta dal widget: una casella, Invio aggiunge alla lista personale. */
class QuickAddActivity : AppCompatActivity() {

    private lateinit var input: EditText
    private var sending = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val prefs = getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
        val userId = prefs.getInt("user_id", 0)
        if (userId == 0 || !prefs.contains("api_url")) {
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            return
        }
        ApiClient.configure(
            url = prefs.getString("api_url", "") ?: "",
            tok = prefs.getString("api_token", "") ?: ""
        )

        setContentView(R.layout.activity_quick_add)
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        )

        input = findViewById(R.id.quick_add_input)
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND || actionId == EditorInfo.IME_ACTION_DONE) {
                invia(userId)
                true
            } else false
        }
        input.requestFocus()
    }

    private fun invia(userId: Int) {
        val testo = input.text.toString().trim()
        if (testo.isEmpty() || sending) return
        sending = true
        input.isEnabled = false
        lifecycleScope.launch {
            val errore = withContext(Dispatchers.IO) {
                try {
                    ApiClient.addItem(gruppoId = 0, topicId = 0, nome = testo, userId = userId)
                    null
                } catch (e: Exception) {
                    e.message ?: "errore"
                }
            }
            if (errore == null) {
                Toast.makeText(this@QuickAddActivity, "Aggiunto ✓", Toast.LENGTH_SHORT).show()
                finish()
            } else {
                // il testo resta nella casella: nulla va perso
                Toast.makeText(this@QuickAddActivity, errore, Toast.LENGTH_LONG).show()
                sending = false
                input.isEnabled = true
                input.requestFocus()
            }
        }
    }
}
