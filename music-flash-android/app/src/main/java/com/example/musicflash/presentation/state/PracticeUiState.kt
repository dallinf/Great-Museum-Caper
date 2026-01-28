package com.example.musicflash.presentation.state

import com.example.musicflash.domain.model.Clef
import com.example.musicflash.domain.model.Note

enum class FeedbackState {
    NEUTRAL,
    CORRECT,
    INCORRECT
}

data class PracticeUiState(
    val selectedClef: Clef = Clef.TREBLE,
    val currentNote: Note? = null,
    val detectedNote: Note? = null,
    val feedbackState: FeedbackState = FeedbackState.NEUTRAL,
    val isListening: Boolean = false,
    val currentAmplitude: Float = 0f,
    val correctCount: Int = 0,
    val totalAttempts: Int = 0,
    val includeAccidentals: Boolean = false
) {
    val accuracy: Double
        get() = if (totalAttempts > 0) {
            correctCount.toDouble() / totalAttempts * 100
        } else {
            0.0
        }
}
