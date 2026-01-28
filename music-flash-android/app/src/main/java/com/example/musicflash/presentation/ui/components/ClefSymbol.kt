package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.musicflash.domain.model.Clef

@Composable
fun ClefSymbol(
    clef: Clef,
    lineSpacing: Dp,
    modifier: Modifier = Modifier
) {
    val fontSize = when (clef) {
        Clef.TREBLE -> lineSpacing.value * 8
        Clef.BASS -> lineSpacing.value * 3.5f
        Clef.ALTO, Clef.TENOR -> lineSpacing.value * 4
    }

    val yOffset = clef.symbolYOffset * lineSpacing.value

    Text(
        text = clef.clefSymbol,
        fontSize = fontSize.sp,
        color = Color.Black,
        modifier = modifier.offset(y = yOffset.dp)
    )
}
