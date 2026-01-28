package com.example.musicflash.domain.logic

import com.example.musicflash.domain.model.Accidental
import com.example.musicflash.domain.model.Clef
import com.example.musicflash.domain.model.Note

class NoteGenerator(
    private val clef: Clef,
    private val includeAccidentals: Boolean = false
) {
    private val naturalSemitones = listOf(0, 2, 4, 5, 7, 9, 11)

    fun generateRandomNote(): Note {
        val midiRange = clef.noteRange
        val midiNumber = midiRange.random()

        var note = Note.fromMidiNumber(midiNumber)

        if (includeAccidentals && (0..1).random() == 1) {
            val accidentals = listOf(Accidental.SHARP, Accidental.FLAT)
            val randomAccidental = accidentals.random()
            val newMidi = note.midiNumber + randomAccidental.semitoneOffset
            if (newMidi in midiRange) {
                note = Note(pitch = note.pitch, octave = note.octave, accidental = randomAccidental)
            }
        }

        return note
    }

    fun generateNaturalNote(): Note {
        val naturalMidiNumbers = clef.noteRange.filter { midi ->
            val noteInOctave = midi % 12
            noteInOctave in naturalSemitones
        }

        val midiNumber = naturalMidiNumbers.randomOrNull()
            ?: return Note.fromMidiNumber(60) // Middle C fallback

        return Note.fromMidiNumber(midiNumber)
    }

    fun generateNoteWithinStaff(): Note {
        val staffMidiRange = when (clef) {
            Clef.TREBLE -> 64..77
            Clef.BASS -> 43..57
            Clef.ALTO -> 53..67
            Clef.TENOR -> 50..64
        }

        val constrainedRange = maxOf(staffMidiRange.first, clef.noteRange.first)..
                minOf(staffMidiRange.last, clef.noteRange.last)

        val naturalMidiNumbers = constrainedRange.filter { midi ->
            val noteInOctave = midi % 12
            noteInOctave in naturalSemitones
        }

        val midiNumber = naturalMidiNumbers.randomOrNull()
            ?: return Note.fromMidiNumber(60) // Middle C fallback

        var note = Note.fromMidiNumber(midiNumber)

        if (includeAccidentals && (0..1).random() == 1) {
            val accidentals = listOf(Accidental.SHARP, Accidental.FLAT)
            val randomAccidental = accidentals.random()
            note = Note(pitch = note.pitch, octave = note.octave, accidental = randomAccidental)
        }

        return note
    }
}
