package com.example.musicflash.domain.logic

import com.example.musicflash.domain.model.Note
import kotlin.math.abs

class PitchMatcher(
    private val centsThreshold: Double = 50.0,
    private val minimumHoldDurationMs: Long = 300,
    private val historySize: Int = 5,
    private val maxIncorrectAttempts: Int = 3
) {
    private val pitchHistory = mutableListOf<Float>()
    private var lastCorrectTime: Long? = null
    private var incorrectAttempts = 0
    private var lastIncorrectNote: Note? = null

    fun reset() {
        pitchHistory.clear()
        lastCorrectTime = null
        incorrectAttempts = 0
        lastIncorrectNote = null
    }

    fun addFrequency(frequency: Float) {
        pitchHistory.add(frequency)
        if (pitchHistory.size > historySize) {
            pitchHistory.removeAt(0)
        }
    }

    fun getAverageFrequency(): Float? {
        if (pitchHistory.size < 3) return null
        return pitchHistory.sum() / pitchHistory.size
    }

    sealed class MatchResult {
        data object NeedMoreSamples : MatchResult()
        data object HoldingCorrect : MatchResult()
        data object Correct : MatchResult()
        data object Incorrect : MatchResult()
        data object TooManyWrong : MatchResult()
    }

    fun checkMatch(targetNote: Note, currentTimeMs: Long): MatchResult {
        val avgFrequency = getAverageFrequency() ?: return MatchResult.NeedMoreSamples

        val detectedNote = Note.fromFrequency(avgFrequency.toDouble())
        val cents = abs(targetNote.centsFrom(avgFrequency.toDouble()))

        return if (detectedNote.matches(targetNote) && cents < centsThreshold) {
            val startTime = lastCorrectTime
            if (startTime == null) {
                lastCorrectTime = currentTimeMs
                MatchResult.HoldingCorrect
            } else if (currentTimeMs - startTime >= minimumHoldDurationMs) {
                MatchResult.Correct
            } else {
                MatchResult.HoldingCorrect
            }
        } else {
            lastCorrectTime = null

            // Count distinct incorrect notes
            if (lastIncorrectNote == null || !detectedNote.matches(lastIncorrectNote!!)) {
                lastIncorrectNote = detectedNote
                incorrectAttempts++
                if (incorrectAttempts >= maxIncorrectAttempts) {
                    MatchResult.TooManyWrong
                } else {
                    MatchResult.Incorrect
                }
            } else {
                MatchResult.Incorrect
            }
        }
    }

    fun getDetectedNote(): Note? {
        val avgFrequency = getAverageFrequency() ?: return null
        return Note.fromFrequency(avgFrequency.toDouble())
    }
}
