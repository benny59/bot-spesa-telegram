package com.botspesa.app

import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

data class CategoryChoice(
    val id: Int?,
    val name: String,
    val ephemeral: Boolean
)

object CategoryPicker {
    fun show(
        fragment: Fragment,
        gruppoId: Int,
        topicId: Int,
        userId: Int,
        currentCategoryId: Int,
        currentCategoryName: String,
        currentCategoryEphemeral: Boolean,
        onSelected: (CategoryChoice) -> Unit
    ) {
        fragment.viewLifecycleOwner.lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getCategorie(gruppoId, topicId, userId) }
            }
            result.onFailure {
                Toast.makeText(fragment.requireContext(), it.message ?: "Categorie non disponibili", Toast.LENGTH_LONG).show()
            }
            result.onSuccess { categories ->
                val choices = buildList {
                    add(CategoryChoice(null, "", false))
                    addAll(
                        categories
                            .sortedWith(compareBy<ApiClient.CategoriaItem> { it.nome.lowercase(Locale.ITALY) }.thenBy { it.nome })
                            .map { category ->
                                CategoryChoice(
                                    category.id.takeIf { !category.effimera && it > 0 },
                                    category.nome,
                                    category.effimera
                                )
                            }
                    )
                }
                val labels = choices.map { choice ->
                    if (choice.name.isBlank()) {
                        fragment.getString(R.string.nessuna_categoria)
                    } else {
                        val displayName = if (choice.ephemeral) choice.name.lowercase(Locale.ITALY) else choice.name
                        val marker = if (choice.ephemeral) "◌ " else ""
                        marker + LocalizationManager.localizedCategoryName(fragment.requireContext(), displayName)
                    }
                }.toTypedArray()
                val selected = choices.indexOfFirst { choice ->
                    if (currentCategoryEphemeral) {
                        choice.ephemeral && choice.name.equals(currentCategoryName, ignoreCase = true)
                    } else {
                        choice.id == currentCategoryId.takeIf { it > 0 }
                    }
                }.takeIf { it >= 0 } ?: 0

                AlertDialog.Builder(fragment.requireContext())
                    .setTitle(R.string.categoria)
                    .setSingleChoiceItems(labels, selected) { dialog, index ->
                        dialog.dismiss()
                        onSelected(choices[index])
                    }
                    .setNegativeButton(R.string.annulla, null)
                    .show()
            }
        }
    }
}
