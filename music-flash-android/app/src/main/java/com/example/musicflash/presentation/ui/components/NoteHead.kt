package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.musicflash.domain.model.Note
import com.example.musicflash.presentation.state.FeedbackState

@Composable
fun NoteHead(
    note: Note,
    lineSpacing: Dp,
    feedbackState: FeedbackState,
    modifier: Modifier = Modifier
) {
    val noteColor = when (feedbackState) {
        FeedbackState.NEUTRAL -> Color.Black
        FeedbackState.CORRECT -> Color(0xFF4CAF50)
        FeedbackState.INCORRECT -> Color(0xFFF44336)
    }

    val noteWidth = lineSpacing * 1.3f
    val noteHeight = lineSpacing * 0.9f

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
    ) {
        // Accidental
        note.accidental?.let { accidental ->
            Text(
                text = accidental.symbol,
                color = noteColor,
                fontSize = (lineSpacing.value * 1.5f).sp
            )
        }

        // Note head ellipse
        Canvas(
            modifier = Modifier.size(noteWidth, noteHeight)
        ) {
            rotate(-20f, pivot = Offset(size.width / 2, size.height / 2)) {
                drawOval(
                    color = noteColor,
                    topLeft = Offset.Zero,
                    size = Size(size.width, size.height)
                )
            }
        }
    }
}
