package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun AmplitudeMeter(
    amplitude: Float,
    modifier: Modifier = Modifier
) {
    val meterColor = when {
        amplitude < 0.1f -> Color.Gray
        amplitude < 0.5f -> Color(0xFF4CAF50) // Green
        else -> Color(0xFFFF9800) // Orange
    }

    val fillWidth = (amplitude * 2).coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .height(8.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(Color(0xFFE0E0E0))
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(fillWidth)
                .clip(RoundedCornerShape(4.dp))
                .background(meterColor)
                .align(Alignment.CenterStart)
        )
    }
}
