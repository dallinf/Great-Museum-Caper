package com.example.musicflash.presentation.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.musicflash.audio.PitchData
import com.example.musicflash.audio.PitchDetector
import com.example.musicflash.domain.logic.NoteGenerator
import com.example.musicflash.domain.model.Clef
import com.example.musicflash.domain.model.Note
import com.example.musicflash.presentation.state.FeedbackState
import com.example.musicflash.presentation.state.PracticeUiState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.abs

class PracticeViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(PracticeUiState())
    val uiState: StateFlow<PracticeUiState> = _uiState.asStateFlow()

    private val pitchDetector = PitchDetector()
    private var noteGenerator: NoteGenerator

    private var pitchDetectionJob: Job? = null

    // Pitch matching parameters (matching iOS)
    private val centsThreshold = 50.0
    private val minimumHoldDurationMs = 300L
    private val historySize = 5
    private val maxIncorrectAttempts = 3

    // Pitch matching state
    private val pitchHistory = mutableListOf<Float>()
    private var lastCorrectTime: Long? = null
    private var incorrectAttempts = 0
    private var lastIncorrectNote: Note? = null

    init {
        noteGenerator = NoteGenerator(
            clef = _uiState.value.selectedClef,
            includeAccidentals = _uiState.value.includeAccidentals
        )
        generateNewNote()
    }

    fun selectClef(clef: Clef) {
        noteGenerator = NoteGenerator(
            clef = clef,
            includeAccidentals = _uiState.value.includeAccidentals
        )
        _uiState.update { it.copy(selectedClef = clef) }
        generateNewNote()
    }

    fun setIncludeAccidentals(include: Boolean) {
        noteGenerator = NoteGenerator(
            clef = _uiState.value.selectedClef,
            includeAccidentals = include
        )
        _uiState.update { it.copy(includeAccidentals = include) }
    }

    fun generateNewNote() {
        val newNote = noteGenerator.generateNoteWithinStaff()
        _uiState.update {
            it.copy(
                currentNote = newNote,
                detectedNote = null,
                feedbackState = FeedbackState.NEUTRAL
            )
        }
        resetPitchMatchingState()
    }

    private fun resetPitchMatchingState() {
        pitchHistory.clear()
        lastCorrectTime = null
        incorrectAttempts = 0
        lastIncorrectNote = null
    }

    fun startListening() {
        if (_uiState.value.isListening) return

        _uiState.update { it.copy(isListening = true) }

        pitchDetectionJob = viewModelScope.launch {
            pitchDetector.startDetection().collect { pitchData ->
                handlePitchData(pitchData)
            }
        }
    }

    fun stopListening() {
        pitchDetectionJob?.cancel()
        pitchDetectionJob = null
        pitchDetector.stopDetection()

        _uiState.update {
            it.copy(
                isListening = false,
                currentAmplitude = 0f,
                detectedNote = null
            )
        }
    }

    private fun handlePitchData(pitchData: PitchData) {
        // Always update amplitude
        _uiState.update { it.copy(currentAmplitude = pitchData.amplitude) }

        // Skip if no valid pitch detected
        if (pitchData.frequency <= 0) return

        // Skip if already marked correct (waiting for next note)
        if (_uiState.value.feedbackState == FeedbackState.CORRECT) return

        // Add to history for rolling average
        pitchHistory.add(pitchData.frequency)
        if (pitchHistory.size > historySize) {
            pitchHistory.removeAt(0)
        }

        // Need at least 3 samples for average
        if (pitchHistory.size < 3) return

        val averageFrequency = pitchHistory.sum() / pitchHistory.size
        val detectedNote = Note.fromFrequency(averageFrequency.toDouble())

        _uiState.update { it.copy(detectedNote = detectedNote) }

        val targetNote = _uiState.value.currentNote ?: return
        val cents = abs(targetNote.centsFrom(averageFrequency.toDouble()))

        if (detectedNote.matches(targetNote) && cents < centsThreshold) {
            // Correct note being played
            val currentTime = System.currentTimeMillis()
            val startTime = lastCorrectTime

            if (startTime == null) {
                lastCorrectTime = currentTime
            } else if (currentTime - startTime >= minimumHoldDurationMs) {
                markCorrect()
            }
        } else {
            // Wrong note
            lastCorrectTime = null

            if (_uiState.value.feedbackState != FeedbackState.CORRECT) {
                _uiState.update { it.copy(feedbackState = FeedbackState.INCORRECT) }

                // Count distinct incorrect notes
                if (lastIncorrectNote == null || !detectedNote.matches(lastIncorrectNote!!)) {
                    lastIncorrectNote = detectedNote
                    incorrectAttempts++

                    if (incorrectAttempts >= maxIncorrectAttempts) {
                        markIncorrect()
                    }
                }
            }
        }
    }

    private fun markCorrect() {
        _uiState.update {
            it.copy(
                feedbackState = FeedbackState.CORRECT,
                correctCount = it.correctCount + 1,
                totalAttempts = it.totalAttempts + 1
            )
        }

        viewModelScope.launch {
            delay(1000)
            generateNewNote()
        }
    }

    private fun markIncorrect() {
        _uiState.update {
            it.copy(totalAttempts = it.totalAttempts + 1)
        }

        viewModelScope.launch {
            delay(1000)
            generateNewNote()
        }
    }

    fun resetScore() {
        _uiState.update {
            it.copy(
                correctCount = 0,
                totalAttempts = 0
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopListening()
    }
}
