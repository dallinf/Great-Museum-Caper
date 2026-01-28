package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.musicflash.domain.model.Clef

@Composable
fun ClefPicker(
    selectedClef: Clef,
    onClefSelected: (Clef) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color(0xFFE0E0E0))
            .padding(4.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        Clef.entries.forEach { clef ->
            val isSelected = clef == selectedClef

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(6.dp))
                    .background(
                        if (isSelected) MaterialTheme.colorScheme.primary
                        else Color.Transparent
                    )
                    .clickable { onClefSelected(clef) }
                    .padding(vertical = 8.dp, horizontal = 12.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = clef.displayName,
                    color = if (isSelected) Color.White else Color.Black,
                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                )
            }
        }
    }
}
