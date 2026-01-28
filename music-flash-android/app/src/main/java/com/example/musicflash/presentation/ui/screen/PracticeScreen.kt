package com.example.musicflash.presentation.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.musicflash.presentation.state.FeedbackState
import com.example.musicflash.presentation.ui.components.AmplitudeMeter
import com.example.musicflash.presentation.ui.components.ClefPicker
import com.example.musicflash.presentation.ui.components.ScoreDisplay
import com.example.musicflash.presentation.ui.components.StaffView
import com.example.musicflash.presentation.viewmodel.PracticeViewModel

@Composable
fun PracticeScreen(
    viewModel: PracticeViewModel = viewModel(),
    onRequestPermission: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Clef Picker
        ClefPicker(
            selectedClef = uiState.selectedClef,
            onClefSelected = { viewModel.selectClef(it) },
            modifier = Modifier.padding(horizontal = 8.dp)
        )

        Spacer(modifier = Modifier.weight(1f))

        // Staff Section
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(2.dp, RoundedCornerShape(12.dp)),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surface
        ) {
            StaffView(
                clef = uiState.selectedClef,
                note = uiState.currentNote,
                feedbackState = uiState.feedbackState,
                modifier = Modifier.padding(8.dp)
            )
        }

        // Note name display
        uiState.currentNote?.let { note ->
            Text(
                text = "Play: ${note.displayName}",
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        // Detected Note Display
        DetectedNoteDisplay(
            detectedNote = uiState.detectedNote?.displayName,
            isListening = uiState.isListening,
            feedbackState = uiState.feedbackState,
            amplitude = uiState.currentAmplitude
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Feedback Section
        FeedbackDisplay(feedbackState = uiState.feedbackState)

        Spacer(modifier = Modifier.height(16.dp))

        // Control Buttons
        ControlButtons(
            isListening = uiState.isListening,
            onNewNote = { viewModel.generateNewNote() },
            onToggleListen = {
                if (uiState.isListening) {
                    viewModel.stopListening()
                } else {
                    onRequestPermission()
                    viewModel.startListening()
                }
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Score Display
        ScoreDisplay(
            correctCount = uiState.correctCount,
            totalAttempts = uiState.totalAttempts
        )
    }
}

@Composable
private fun DetectedNoteDisplay(
    detectedNote: String?,
    isListening: Boolean,
    feedbackState: FeedbackState,
    amplitude: Float
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.height(100.dp)
    ) {
        Text(
            text = "Detected Note",
            fontSize = 12.sp,
            color = Color.Gray
        )

        Spacer(modifier = Modifier.height(8.dp))

        if (isListening) {
            if (detectedNote != null) {
                Text(
                    text = detectedNote,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (feedbackState == FeedbackState.CORRECT) {
                        Color(0xFF4CAF50)
                    } else {
                        Color.Black
                    }
                )
            } else {
                Text(
                    text = "Listening...",
                    fontSize = 20.sp,
                    color = Color.Gray
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            AmplitudeMeter(
                amplitude = amplitude,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 50.dp)
            )
        } else {
            Text(
                text = "—",
                fontSize = 32.sp,
                color = Color.Gray
            )
        }
    }
}

@Composable
private fun FeedbackDisplay(feedbackState: FeedbackState) {
    Box(
        modifier = Modifier.height(40.dp),
        contentAlignment = Alignment.Center
    ) {
        when (feedbackState) {
            FeedbackState.CORRECT -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Check,
                        contentDescription = "Correct",
                        tint = Color(0xFF4CAF50)
                    )
                    Text(
                        text = "Correct!",
                        fontSize = 18.sp,
                        color = Color(0xFF4CAF50),
                        fontWeight = FontWeight.Medium
                    )
                }
            }
            FeedbackState.INCORRECT -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Incorrect",
                        tint = Color(0xFFF44336)
                    )
                    Text(
                        text = "Try again",
                        fontSize = 18.sp,
                        color = Color(0xFFF44336),
                        fontWeight = FontWeight.Medium
                    )
                }
            }
            FeedbackState.NEUTRAL -> {
                // Empty space
            }
        }
    }
}

@Composable
private fun ControlButtons(
    isListening: Boolean,
    onNewNote: () -> Unit,
    onToggleListen: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        OutlinedButton(
            onClick = onNewNote,
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = Icons.Default.Refresh,
                contentDescription = "New Note",
                modifier = Modifier.padding(end = 4.dp)
            )
            Text("New Note")
        }

        Button(
            onClick = onToggleListen,
            modifier = Modifier.weight(1f),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isListening) Color(0xFFF44336) else MaterialTheme.colorScheme.primary
            )
        ) {
            Icon(
                imageVector = if (isListening) Icons.Default.MicOff else Icons.Default.Mic,
                contentDescription = if (isListening) "Stop" else "Listen",
                modifier = Modifier.padding(end = 4.dp)
            )
            Text(if (isListening) "Stop" else "Listen")
        }
    }
}
