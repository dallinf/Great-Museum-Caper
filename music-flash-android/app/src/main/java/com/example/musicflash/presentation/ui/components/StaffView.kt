package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.musicflash.domain.model.Clef
import com.example.musicflash.domain.model.Note
import com.example.musicflash.presentation.state.FeedbackState

@Composable
fun StaffView(
    clef: Clef,
    note: Note?,
    feedbackState: FeedbackState,
    modifier: Modifier = Modifier
) {
    val lineSpacing = 20.dp
    val lineSpacingPx = with(LocalDensity.current) { lineSpacing.toPx() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(200.dp)
    ) {
        // Staff lines and note
        Canvas(modifier = Modifier.matchParentSize()) {
            val centerY = size.height / 2
            val staffStartX = 20f
            val staffEndX = size.width - 20f

            // Draw 5 staff lines
            for (i in 0 until 5) {
                val yOffset = (i - 2) * lineSpacingPx
                drawLine(
                    color = Color.Black,
                    start = Offset(staffStartX, centerY + yOffset),
                    end = Offset(staffEndX, centerY + yOffset),
                    strokeWidth = 1.5f
                )
            }

            // Draw note if present
            note?.let { currentNote ->
                val staffPosition = clef.staffPositionForNote(currentNote)
                val noteY = yPositionForStaffPosition(staffPosition, centerY, lineSpacingPx)
                val noteX = size.width / 2

                val noteColor = when (feedbackState) {
                    FeedbackState.NEUTRAL -> Color.Black
                    FeedbackState.CORRECT -> Color(0xFF4CAF50)
                    FeedbackState.INCORRECT -> Color(0xFFF44336)
                }

                // Draw ledger lines if needed
                val ledgerLines = clef.ledgerLinesNeeded(staffPosition)
                for (ledgerPosition in ledgerLines) {
                    val ledgerY = yPositionForStaffPosition(ledgerPosition, centerY, lineSpacingPx)
                    drawLine(
                        color = Color.Black,
                        start = Offset(noteX - 25f, ledgerY),
                        end = Offset(noteX + 25f, ledgerY),
                        strokeWidth = 1.5f
                    )
                }

                // Draw accidental if present
                val accidentalOffset = if (currentNote.accidental != null) 20f else 0f

                // Draw note head (ellipse rotated -20 degrees)
                val noteWidth = lineSpacingPx * 1.3f
                val noteHeight = lineSpacingPx * 0.9f

                rotate(-20f, pivot = Offset(noteX + accidentalOffset, noteY)) {
                    drawOval(
                        color = noteColor,
                        topLeft = Offset(noteX + accidentalOffset - noteWidth / 2, noteY - noteHeight / 2),
                        size = Size(noteWidth, noteHeight)
                    )
                }
            }
        }

        // Clef symbol (as text overlay)
        ClefSymbolOverlay(
            clef = clef,
            lineSpacing = lineSpacing,
            modifier = Modifier.align(Alignment.CenterStart).offset(x = 30.dp)
        )

        // Accidental text overlay
        note?.accidental?.let { accidental ->
            val staffPosition = clef.staffPositionForNote(note)
            val middleLinePosition = 4
            val offset = (middleLinePosition - staffPosition) * (lineSpacing.value / 2)

            Text(
                text = accidental.symbol,
                fontSize = (lineSpacing.value * 1.5f).sp,
                color = when (feedbackState) {
                    FeedbackState.NEUTRAL -> Color.Black
                    FeedbackState.CORRECT -> Color(0xFF4CAF50)
                    FeedbackState.INCORRECT -> Color(0xFFF44336)
                },
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = (-25).dp, y = offset.dp)
            )
        }
    }
}

@Composable
private fun ClefSymbolOverlay(
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

private fun yPositionForStaffPosition(staffPosition: Int, centerY: Float, lineSpacing: Float): Float {
    val middleLinePosition = 4
    val offset = (middleLinePosition - staffPosition) * (lineSpacing / 2)
    return centerY + offset
}
