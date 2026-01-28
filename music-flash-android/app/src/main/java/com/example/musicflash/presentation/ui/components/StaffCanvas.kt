package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.dp
import com.example.musicflash.domain.model.Clef
import com.example.musicflash.domain.model.Note
import com.example.musicflash.presentation.state.FeedbackState

@Composable
fun StaffCanvas(
    clef: Clef,
    note: Note?,
    feedbackState: FeedbackState,
    modifier: Modifier = Modifier
) {
    val lineSpacing = 20f
    val staffColor = Color.Black
    val noteColor = when (feedbackState) {
        FeedbackState.NEUTRAL -> Color.Black
        FeedbackState.CORRECT -> Color(0xFF4CAF50)
        FeedbackState.INCORRECT -> Color(0xFFF44336)
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(200.dp)
    ) {
        val centerY = size.height / 2
        val staffStartX = 20f
        val staffEndX = size.width - 20f

        // Draw 5 staff lines
        for (i in 0 until 5) {
            val yOffset = (i - 2) * lineSpacing
            drawLine(
                color = staffColor,
                start = Offset(staffStartX, centerY + yOffset),
                end = Offset(staffEndX, centerY + yOffset),
                strokeWidth = 1.5f
            )
        }

        // Draw clef symbol position marker (placeholder area)
        // The actual clef symbol is drawn separately as text

        // Draw note if present
        note?.let { currentNote ->
            val staffPosition = clef.staffPositionForNote(currentNote)
            val noteY = yPositionForStaffPosition(staffPosition, centerY, lineSpacing)
            val noteX = size.width / 2

            // Draw ledger lines if needed
            val ledgerLines = clef.ledgerLinesNeeded(staffPosition)
            for (ledgerPosition in ledgerLines) {
                val ledgerY = yPositionForStaffPosition(ledgerPosition, centerY, lineSpacing)
                drawLine(
                    color = staffColor,
                    start = Offset(noteX - 25f, ledgerY),
                    end = Offset(noteX + 25f, ledgerY),
                    strokeWidth = 1.5f
                )
            }

            // Draw note head (ellipse rotated -20 degrees)
            drawNoteHead(
                centerX = noteX,
                centerY = noteY,
                width = lineSpacing * 1.3f,
                height = lineSpacing * 0.9f,
                color = noteColor,
                rotation = -20f
            )

            // Draw accidental if present
            currentNote.accidental?.let { accidental ->
                // Accidental is drawn as text in the NoteHead composable
            }
        }
    }
}

private fun DrawScope.drawNoteHead(
    centerX: Float,
    centerY: Float,
    width: Float,
    height: Float,
    color: Color,
    rotation: Float
) {
    rotate(rotation, pivot = Offset(centerX, centerY)) {
        drawOval(
            color = color,
            topLeft = Offset(centerX - width / 2, centerY - height / 2),
            size = androidx.compose.ui.geometry.Size(width, height)
        )
    }
}

private fun yPositionForStaffPosition(staffPosition: Int, centerY: Float, lineSpacing: Float): Float {
    val middleLinePosition = 4
    val offset = (middleLinePosition - staffPosition) * (lineSpacing / 2)
    return centerY + offset
}
