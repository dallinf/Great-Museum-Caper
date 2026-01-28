package com.example.musicflash.domain.model

import java.util.UUID
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.roundToInt

data class Note(
    val pitch: Pitch,
    val octave: Int,
    val accidental: Accidental? = null,
    val id: String = UUID.randomUUID().toString()
) {
    val midiNumber: Int
        get() {
            val baseMidi = (octave + 1) * 12 + pitch.semitone
            return baseMidi + (accidental?.semitoneOffset ?: 0)
        }

    val frequency: Double
        get() {
            val a4Frequency = 440.0
            val a4MidiNumber = 69
            val semitoneRatio = 2.0.pow(1.0 / 12.0)
            return a4Frequency * semitoneRatio.pow((midiNumber - a4MidiNumber).toDouble())
        }

    val displayName: String
        get() {
            val accidentalSymbol = accidental?.symbol ?: ""
            return "${pitch.name}$accidentalSymbol$octave"
        }

    val staffPositionFromMiddleC: Int
        get() {
            val octaveOffset = (octave - 4) * 7
            return pitch.staffPosition + octaveOffset
        }

    fun matches(other: Note, ignoringOctave: Boolean = false): Boolean {
        val pitchMatch = this.pitch == other.pitch && this.accidental == other.accidental
        return if (ignoringOctave) {
            pitchMatch
        } else {
            pitchMatch && this.octave == other.octave
        }
    }

    fun centsFrom(frequency: Double): Double {
        return 1200.0 * log2(frequency / this.frequency)
    }

    companion object {
        fun fromMidiNumber(midi: Int): Note {
            val octave = (midi / 12) - 1
            val noteInOctave = midi % 12

            val naturalNotes = listOf(
                Pitch.C to 0,
                Pitch.D to 2,
                Pitch.E to 4,
                Pitch.F to 5,
                Pitch.G to 7,
                Pitch.A to 9,
                Pitch.B to 11
            )

            for ((pitch, semitone) in naturalNotes) {
                if (semitone == noteInOctave) {
                    return Note(pitch = pitch, octave = octave, accidental = null)
                }
                if (semitone + 1 == noteInOctave) {
                    return Note(pitch = pitch, octave = octave, accidental = Accidental.SHARP)
                }
            }

            return Note(pitch = Pitch.C, octave = octave, accidental = null)
        }

        fun fromFrequency(frequency: Double): Note {
            val a4Frequency = 440.0
            val a4MidiNumber = 69
            val semitones = 12.0 * log2(frequency / a4Frequency)
            val midiNumber = semitones.roundToInt() + a4MidiNumber
            return fromMidiNumber(midiNumber)
        }
    }
}
