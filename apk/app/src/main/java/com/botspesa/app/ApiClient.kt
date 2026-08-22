package com.botspesa.app

import android.content.Context
import coil.ImageLoader
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
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

    private val ogTitleRegex = Regex("<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>", RegexOption.IGNORE_CASE)
    private val ogImageRegex = Regex("<meta[^>]+property=[\"']og:image(?:[^\"']*)?[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>", RegexOption.IGNORE_CASE)
    private val titleRegex = Regex("<title[^>]*>(.*?)</title>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))

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

    data class ConteggiListe(val tutti: Int, val miei: Int)

    data class ProductPreview(
        val barcode: String,
        val name: String,
        val brand: String,
        val quantity: String,
        val imageUrl: String,
        val nutriscoreGrade: String,
        val energyKcal100g: Double?,
        val sugars100g: Double?,
        val saturatedFat100g: Double?,
        val salt100g: Double?,
        val sourceUrl: String
    ) {
        val displayName: String
            get() = listOf(name, brand, quantity)
                .filter { it.isNotBlank() }
                .distinctBy { it.lowercase() }
                .joinToString(" ")
    }

    fun getConteggiListe(userId: Int): ConteggiListe {
        val req = Request.Builder().url("$baseUrl/lista/conteggi?user_id=$userId").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        val raw: Map<String, Any> = gson.fromJson(body, object : TypeToken<Map<String, Any>>() {}.type)
        return ConteggiListe(
            tutti = (raw["tutti"] as? Double)?.toInt() ?: 0,
            miei = (raw["miei"] as? Double)?.toInt() ?: 0
        )
    }

    fun getProductPreview(barcode: String): ProductPreview? {
        val cleanBarcode = barcode.filter(Char::isDigit)
        val req = Request.Builder()
            .url("$baseUrl/prodotti/$cleanBarcode/anteprima")
            .auth()
            .build()
        return http.newCall(req).execute().use { response ->
            if (!response.isSuccessful) return@use null
            val raw: Map<String, Any?> = gson.fromJson(
                response.body?.string().orEmpty(),
                object : TypeToken<Map<String, Any?>>() {}.type
            )
            ProductPreview(
                barcode = raw["barcode"] as? String ?: cleanBarcode,
                name = raw["name"] as? String ?: return@use null,
                brand = raw["brand"] as? String ?: "",
                quantity = raw["quantity"] as? String ?: "",
                imageUrl = raw["image_url"] as? String ?: "",
                nutriscoreGrade = raw["nutriscore_grade"] as? String ?: "",
                energyKcal100g = raw["energy_kcal_100g"] as? Double,
                sugars100g = raw["sugars_100g"] as? Double,
                saturatedFat100g = raw["saturated_fat_100g"] as? Double,
                salt100g = raw["salt_100g"] as? Double,
                sourceUrl = raw["source_url"] as? String ?: ""
            )
        }
    }

    private fun parseItems(body: String): List<SpesaItem> {
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { item ->
            val nomeRaw = item["nome"] as? String ?: ""
            val linkRaw = item["link_url"] as? String ?: ""
            val decoded = decodeLinkFromNome(nomeRaw, linkRaw)
            val deletedValue = item["deleted"]
            val deleted = when (deletedValue) {
                is Boolean -> deletedValue
                is Double -> deletedValue.toInt() == 1
                is String -> deletedValue == "1" || deletedValue.equals("true", ignoreCase = true)
                else -> false
            }
            val disponibileValue = item["disponibile"]
            val disponibile = when (disponibileValue) {
                is Boolean -> disponibileValue
                is Double -> disponibileValue.toInt() != 0
                is String -> disponibileValue.equals("true", ignoreCase = true) || disponibileValue == "1"
                else -> true
            }
            SpesaItem(
                id           = (item["id"] as Double).toInt(),
                nome         = decoded.first,
                linkUrl      = decoded.second,
                comprato     = item["comprato"] as? String ?: "",
                userInitials = item["user_initials"] as? String ?: "",
                buyerInitials = item["buyer_initials"] as? String ?: "",
                hasFoto      = item["has_foto"] as? Boolean ?: false,
                gruppoId     = (item["gruppo_id"] as? Double)?.toInt() ?: 0,
                topicId      = (item["topic_id"] as? Double)?.toInt() ?: 0,
                nomeTopic    = item["nome_topic"] as? String ?: "",
                nomeGruppo   = item["nome_gruppo"] as? String ?: "",
                nomeContesto = item["nome_contesto"] as? String ?: "",
                deleted      = deleted,
                disponibile  = disponibile
            )
        }
    }

    private fun decodeLinkFromNome(nomeRaw: String, linkRaw: String): Pair<String, String> {
        val marker = "[YUKA_LINK]"
        val split = nomeRaw.split(marker, limit = 2)
        if (split.size == 2) {
            val nome = split[0].trim().ifEmpty { "Prodotto Yuka" }
            val link = split[1].trim()
            return Pair(nome, if (link.isNotEmpty()) link else linkRaw)
        }

        if (linkRaw.isNotBlank()) return Pair(nomeRaw, linkRaw)

        val regex = Regex("https?://\\S+")
        val match = regex.find(nomeRaw)
        return if (match != null) {
            val link = match.value.trim()
            val nome = nomeRaw.replace(link, "").trim().ifEmpty { "Prodotto Yuka" }
            Pair(nome, link)
        } else {
            Pair(nomeRaw, "")
        }
    }

    fun addItem(
        gruppoId: Int,
        topicId: Int,
        nome: String,
        userId: Int,
        linkUrl: String? = null,
        splitItems: Boolean = true
    ): List<Int> {
        val payloadMap = mutableMapOf<String, Any>(
            "gruppo_id" to gruppoId,
            "topic_id"  to topicId,
            "nome"      to nome,
            "user_id"   to userId,
            "split_items" to splitItems
        )
        val linkPulito = linkUrl?.trim().orEmpty()
        if (linkPulito.isNotEmpty()) {
            payloadMap["link_url"] = linkPulito
        }
        val payload = gson.toJson(payloadMap)
        val req = Request.Builder()
            .url("$baseUrl/lista")
            .post(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw Exception("Server ${response.code}: $body")
            val result: Map<String, Any> = gson.fromJson(body, object : TypeToken<Map<String, Any>>() {}.type)
            (result["item_ids"] as? List<*>)
                ?.mapNotNull { (it as? Double)?.toInt() }
                .orEmpty()
        }
    }

    fun resolveSharedProductTitle(url: String): String? {
        val cleanUrl = url.trim()
        if (cleanUrl.isEmpty()) return null

        val req = Request.Builder()
            .url(cleanUrl)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) BotSpesa/1.0")
            .get()
            .build()

        return runCatching {
            http.newCall(req).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val html = response.body?.string().orEmpty().take(600_000)
                val og = ogTitleRegex.find(html)?.groupValues?.getOrNull(1)?.trim()
                val title = titleRegex.find(html)?.groupValues?.getOrNull(1)?.trim()
                sanitizeResolvedTitle(og ?: title)
            }
        }.getOrNull()
    }

    data class SharedProductPreview(
        val title: String,
        val imageUrl: String?
    )

    fun resolveSharedProductPreview(url: String): SharedProductPreview? {
        val cleanUrl = url.trim()
        if (cleanUrl.isEmpty()) return null

        val req = Request.Builder()
            .url(cleanUrl)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) BotSpesa/1.0")
            .get()
            .build()

        return runCatching {
            http.newCall(req).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val html = response.body?.string().orEmpty().take(600_000)
                val ogTitle = ogTitleRegex.find(html)?.groupValues?.getOrNull(1)?.trim()
                val title = titleRegex.find(html)?.groupValues?.getOrNull(1)?.trim()
                val resolvedTitle = sanitizeResolvedTitle(ogTitle ?: title) ?: return@use null
                val image = ogImageRegex.find(html)?.groupValues?.getOrNull(1)?.trim().orEmpty()
                SharedProductPreview(
                    title = resolvedTitle,
                    imageUrl = image.takeIf { it.isNotEmpty() }
                )
            }
        }.getOrNull()
    }

    private fun sanitizeResolvedTitle(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null

        val cleaned = value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")
            .replace(Regex("\\s+"), " ")
            .replace(Regex("\\s*[|•-]\\s*Yuka.*$", RegexOption.IGNORE_CASE), "")
            .trim()

        return cleaned.takeIf { it.length >= 3 }
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

    fun restoreItem(gruppoId: Int, itemId: Int, userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/restore?gruppo_id=$gruppoId&user_id=$userId")
            .post("".toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun setDisponibile(gruppoId: Int, itemId: Int, userId: Int, disponibile: Boolean): Boolean {
        val payload = gson.toJson(mapOf(
            "gruppo_id" to gruppoId,
            "user_id" to userId,
            "disponibile" to disponibile
        ))
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/disponibile")
            .patch(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun updateItem(itemId: Int, nome: String, userId: Int): Boolean {
        val payload = gson.toJson(mapOf("nome" to nome, "user_id" to userId))
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId")
            .patch(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun moveItem(itemId: Int, gruppoId: Int, topicId: Int, userId: Int): Boolean {
        val payload = gson.toJson(mapOf("gruppo_id" to gruppoId, "topic_id" to topicId, "user_id" to userId))
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/topic")
            .patch(payload.toRequestBody(JSON_TYPE))
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun deleteFoto(itemId: Int, userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/lista/$itemId/foto?user_id=$userId")
            .delete()
            .auth()
            .build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun uploadFoto(itemId: Int, userId: Int, imageBytes: ByteArray): Boolean {
        val body = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
            .addFormDataPart("user_id", userId.toString())
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

    data class StoricoAcquisto(
        val id: Int,
        val nome: String,
        val creatore: String,
        val acquirente: String,
        val updatedAt: String,
        val conteggio: Int
    )

    fun getStoricoAcquisti(gruppoId: Int, topicId: Int): List<StoricoAcquisto> {
        val req = Request.Builder()
            .url("$baseUrl/storico/acquisti?gruppo_id=$gruppoId&topic_id=$topicId")
            .auth()
            .build()
        val resp = http.newCall(req).execute()
        val body = resp.use { it.body!!.string() }
        if (!resp.isSuccessful) throw Exception("Server ${resp.code}: $body")
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { acquisto ->
            StoricoAcquisto(
                id         = (acquisto["id"] as? Double)?.toInt() ?: 0,
                nome       = acquisto["nome"] as? String ?: "",
                creatore   = acquisto["creatore"] as? String ?: "",
                acquirente = acquisto["acquirente"] as? String ?: "",
                updatedAt  = acquisto["updated_at"] as? String ?: "",
                conteggio  = (acquisto["conteggio"] as? Double)?.toInt() ?: 0
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

    fun getGruppiTyped(userId: Int): List<GruppoItem> {
        val req = Request.Builder().url("$baseUrl/gruppi?user_id=$userId").auth().build()
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

    fun getCarte(gruppoId: Int, userId: Int): List<CartaFedeltaItem> {
        val req = Request.Builder().url("$baseUrl/carte?gruppo_id=$gruppoId&user_id=$userId").auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        return parseCarte(body)
    }

    fun getMieCarte(userId: Int, gruppoId: Int = 0): List<CartaFedeltaItem> {
        val req = Request.Builder()
            .url("$baseUrl/carte/mie?user_id=$userId&gruppo_id=$gruppoId")
            .auth().build()
        val body = http.newCall(req).execute().use { it.body!!.string() }
        return parseCarte(body)
    }

    /** Invia immagine al server per il decode barcode. Restituisce Pair(codice, formato) o null. */
    fun scanBarcode(imageBytes: ByteArray): Pair<String, String>? {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("immagine", "scan.jpg", imageBytes.toRequestBody("image/jpeg".toMediaType()))
            .build()
        val resp = http.newCall(Request.Builder().url("$baseUrl/carte/scan").post(body).auth().build())
            .execute()
        if (!resp.isSuccessful) return null
        val map: Map<String, String> = gson.fromJson(resp.body!!.string(),
            object : com.google.gson.reflect.TypeToken<Map<String, String>>() {}.type)
        val codice  = map["codice"]  ?: return null
        val formato = map["formato"] ?: "CODE128"
        return Pair(codice, formato)
    }

    fun creaCarta(userId: Int, nome: String, codice: String): Boolean {
        val payload = mapOf("user_id" to userId, "nome" to nome, "codice" to codice)
        val body = gson.toJson(payload).toRequestBody("application/json".toMediaType())
        return http.newCall(Request.Builder().url("$baseUrl/carte").post(body).auth().build())
            .execute().use { it.isSuccessful }
    }

    fun eliminaCarta(cartaId: Int, userId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/carte/$cartaId?user_id=$userId").delete().auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun collegaCarta(cartaId: Int, gruppoId: Int, userId: Int): Boolean {
        val payload = mapOf("gruppo_id" to gruppoId, "user_id" to userId)
        val body = gson.toJson(payload).toRequestBody("application/json".toMediaType())
        return http.newCall(Request.Builder().url("$baseUrl/carte/$cartaId/collega").post(body).auth().build())
            .execute().use { it.isSuccessful }
    }

    fun scollegaCarta(cartaId: Int, gruppoId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/carte/$cartaId/collega?gruppo_id=$gruppoId").delete().auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    private fun parseCarte(body: String): List<CartaFedeltaItem> {
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(body, type)
        return raw.map { c ->
            CartaFedeltaItem(
                id                 = (c["id"] as Double).toInt(),
                nome               = c["nome"] as? String ?: "",
                codice             = c["codice"] as? String ?: "",
                formato            = c["formato"] as? String ?: "CODE128",
                condivisaConGruppo = c["condivisa"] as? Boolean ?: false,
                isMia              = c["mia"] as? Boolean ?: true
            )
        }
    }

    data class MeResult(val firstName: String, val lastName: String, val isCreator: Boolean)
    data class PendingUtente(val userId: Int, val username: String, val fullName: String, val requestedAt: String)
    data class AdminUtente(val userId: Int, val username: String, val fullName: String, val addedAt: String, val isCreator: Boolean)

    /** Recupera i dati utente dal server, incluso il flag creatore. */
    fun fetchMe(userId: Int): MeResult? {
        val req = Request.Builder().url("$baseUrl/me?user_id=$userId").auth().build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return null
        val map: Map<String, Any> = gson.fromJson(resp.body!!.string(), object : TypeToken<Map<String, Any>>() {}.type)
        return MeResult(
            firstName  = map["first_name"] as? String ?: "",
            lastName   = map["last_name"]  as? String ?: "",
            isCreator  = map["is_creator"] as? Boolean ?: false
        )
    }

    fun getAdminPending(userId: Int): List<PendingUtente> {
        val req = Request.Builder().url("$baseUrl/admin/pending?user_id=$userId").auth().build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return emptyList()
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(resp.body!!.string(), type)
        return raw.map { PendingUtente(
            userId      = (it["user_id"] as Double).toInt(),
            username    = it["username"]     as? String ?: "",
            fullName    = it["full_name"]    as? String ?: "",
            requestedAt = it["requested_at"] as? String ?: ""
        )}
    }

    fun approvaUtente(creatorId: Int, targetId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/admin/pending/$targetId/approva?user_id=$creatorId")
            .post("".toRequestBody(JSON_TYPE)).auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun rifiutaUtente(creatorId: Int, targetId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/admin/pending/$targetId?user_id=$creatorId")
            .delete().auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
    }

    fun getAdminUtenti(userId: Int): List<AdminUtente> {
        val req = Request.Builder().url("$baseUrl/admin/utenti?user_id=$userId").auth().build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return emptyList()
        val type = object : TypeToken<List<Map<String, Any>>>() {}.type
        val raw: List<Map<String, Any>> = gson.fromJson(resp.body!!.string(), type)
        return raw.map { AdminUtente(
            userId    = (it["user_id"] as Double).toInt(),
            username  = it["username"]  as? String ?: "",
            fullName  = it["full_name"] as? String ?: "",
            addedAt   = it["added_at"]  as? String ?: "",
            isCreator = it["is_creator"] as? Boolean ?: false
        )}
    }

    fun revocaUtente(creatorId: Int, targetId: Int): Boolean {
        val req = Request.Builder()
            .url("$baseUrl/admin/utenti/$targetId?user_id=$creatorId")
            .delete().auth().build()
        return http.newCall(req).execute().use { it.isSuccessful }
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
