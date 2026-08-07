package com.botspesa.app

import android.content.Context
import coil.ImageLoader
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

object ApiClient {

    private val gson = Gson()
    private val JSON_TYPE = "application/json; charset=utf-8".toMediaType()
    private val http = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private var baseUrl = "http://10.0.2.2:4567"
    private var token = ""

    fun configure(url: String, tok: String) {
        baseUrl = url.trimEnd('/')
        token = tok
    }

    private fun Request.Builder.auth(): Request.Builder = apply {
        if (token.isNotEmpty()) header("Authorization", "Bearer $token")
    }

    fun ping(): Boolean {
        val req = Request.Builder().url("$baseUrl/ping").auth().build()
        return runCatching { http.newCall(req).execute().use { it.isSuccessful } }.getOrDefault(false)
    }

    fun getGruppi(): List<Map<String, Any>> {
        val req = Request.Builder().url("$baseUrl/gruppi").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        return gson.fromJson(body, type)
    }

    fun getLista(gruppoId: Int, topicId: Int = 0, userId: Int = 0): List<SpesaItem> {
        val req = Request.Builder()
            .url("$baseUrl/lista?gruppo_id=$gruppoId&topic_id=$topicId&user_id=$userId")
            .auth()
            .build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        return parseItems(body)
    }

    fun getMiei(userId: Int): List<SpesaItem> {
        val req = Request.Builder().url("$baseUrl/lista/miei?user_id=$userId").auth().build()
        return parseItems(http.newCall(req).execute().use { it.body!!.string() })
    }

    fun getTutti(userId: Int): List<SpesaItem> {
        val req = Request.Builder().url("$baseUrl/lista/tutti?user_id=$userId").auth().build()
        return parseItems(http.newCall(req).execute().use { it.body!!.string() })
    }

    private fun parseItems(body: String): List<SpesaItem> {
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { item ->
            SpesaItem(
                id           = (item["id"] as Double).toInt(),
                nome         = item["nome"] as? String ?: "",
                comprato     = item["comprato"] as? String ?: "",
                userInitials = item["user_initials"] as? String ?: "",
                hasFoto      = item["has_foto"] as? Boolean ?: false,
                gruppoId     = (item["gruppo_id"] as? Double)?.toInt() ?: 0,
                nomeGruppo   = item["nome_gruppo"] as? String ?: ""
            )
        }
    }

    fun addItem(gruppoId: Int, topicId: Int, nome: String, userId: Int): Boolean {
        val payload = gson.toJson(mapOf(
            "gruppo_id" to gruppoId,
            "topic_id"  to topicId,
            "nome"      to nome,
            "user_id"   to userId
        ))
        val req = Request.Builder()
            .url("$baseUrl/lista")
            .post(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun toggleItem(gruppoId: Int, itemId: Int, userId: Int): String {
        val payload = gson.toJson(mapOf("gruppo_id" to gruppoId, "user_id" to userId))
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/toggle")
            .patch(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val map: Map<String, Any> = gson.fromJson(body, object : TypeToken<Map<String, Any>>() {}.type)
        return map["comprato"] as? String ?: ""
    }

    fun deleteItem(gruppoId: Int, itemId: Int, userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId?gruppo_id=$gruppoId&user_id=$userId")
            .delete()
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun uploadFoto(itemId: Int, imageBytes: ByteArray): Boolean {
        val body = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
            .addFormDataPart("file", "foto.jpg",
                imageBytes.toRequestBody("image/jpeg".toMediaType()))
            .build()
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/foto")
            .post(body)
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun eseguiScopetta(gruppoId: Int, topicId: Int, userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/lista/comprati?gruppo_id=$gruppoId&topic_id=$topicId&user_id=$userId")
            .delete()
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun superScopetta(userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/lista/comprati/ovunque?user_id=$userId")
            .delete()
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun getChecklist(gruppoId: Int, topicId: Int): List<ChecklistItem> {
        val req = Request.Builder()
            .url("$baseUrl/checklist?gruppo_id=$gruppoId&topic_id=$topicId")
            .auth()
            .build()
        val resp = http.newCall(req).execute()
        val body = resp.use { it.body!!.string() }
        if (!resp.isSuccessful) throw Exception("Server ${resp.code}: $body")
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { i ->
            ChecklistItem(
                nome      = i["nome"] as? String ?: "",
                conteggio = (i["conteggio"] as? Double)?.toInt() ?: 0,
                inLista   = i["in_lista"] as? Boolean ?: false
            )
        }
    }

    fun toggleChecklistItem(gruppoId: Int, topicId: Int, nome: String, inLista: Boolean, userId: Int): Boolean {
        val payload = mapOf("gruppo_id" to gruppoId, "topic_id" to topicId,
                            "nome" to nome, "in_lista" to inLista, "user_id" to userId)
        val body = gson.toJson(payload).toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url("$baseUrl/checklist/toggle").post(body).auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun getFotoUrl(itemId: Int): String = "$baseUrl/foto/$itemId"

    fun getToken(): String = token

    fun imageLoader(context: Context): ImageLoader =
        ImageLoader.Builder(context)
            .okHttpClient {
                OkHttpClient.Builder()
                    .connectTimeout(5, TimeUnit.SECONDS)
                    .readTimeout(30, TimeUnit.SECONDS)
                    .also { b ->
                        if (token.isNotEmpty()) b.addInterceptor { chain ->
                            chain.proceed(chain.request().newBuilder()
                                .header("Authorization", "Bearer $token").build())
                        }
                    }
                    .build()
            }
            .build()

    fun getGruppiTyped(): List<GruppoItem> {
        val req = Request.Builder().url("$baseUrl/gruppi").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { GruppoItem(id = (it["id"] as Double).toInt(), nome = it["nome"] as? String ?: "") }
    }

    fun getTopics(gruppoId: Int): List<TopicItem> {
        val req = Request.Builder().url("$baseUrl/topics?gruppo_id=$gruppoId").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { TopicItem(topicId = (it["topic_id"] as Double).toInt(), nome = it["nome"] as? String ?: "") }
    }

    fun getCarte(gruppoId: Int): List<CartaFedeltaItem> {
        val req = Request.Builder().url("$baseUrl/carte?gruppo_id=$gruppoId").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { c ->
            CartaFedeltaItem(
                id      = (c["id"] as Double).toInt(),
                nome    = c["nome"] as? String ?: "",
                codice  = c["codice"] as? String ?: "",
                formato = c["formato"] as? String ?: "qrcode"
            )
        }
    }

    /** Recupera first_name e last_name dal server per lo user_id dato. */
    fun fetchMe(userId: Int): Pair<String, String>? {
        val req = Request.Builder().url("$baseUrl/me?user_id=$userId").auth().build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return null
        val map: Map<String, Any> = gson.fromJson(resp.body!!.string(), object : TypeToken<Map<String, Any>>() {}.type)
        return Pair(map["first_name"] as? String ?: "", map["last_name"] as? String ?: "")
    }

    /** Valida il PIN e restituisce user_id + first_name, o null se non valido. */
    data class CollegaResult(val userId: Int, val firstName: String)
    fun collegaPin(pin: String): CollegaResult? {
        val payload = gson.toJson(mapOf("pin" to pin))
        val req = Request.Builder()
            .url("$baseUrl/collega")
            .post(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) {
            val errBody = runCatching { resp.body?.string() }.getOrNull() ?: ""
            throw Exception("HTTP ${resp.code}: $errBody")
        }
        val map: Map<String, Any> = gson.fromJson(resp.body!!.string(), object : TypeToken<Map<String, Any>>() {}.type)
        val uid = (map["user_id"] as? Double)?.toInt() ?: return null
        val name = map["first_name"] as? String ?: ""
        return CollegaResult(uid, name)
    }
}
