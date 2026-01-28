package com.example.musicflash.domain.model

enum class Clef(val displayName: String) {
    TREBLE("Treble"),
    BASS("Bass"),
    ALTO("Alto"),
    TENOR("Tenor");

    val middleCStaffPosition: Int
        get() = when (this) {
            TREBLE -> -2
            BASS -> 10
            ALTO -> 4
            TENOR -> 6
        }

    val noteRange: IntRange
        get() = when (this) {
            TREBLE -> 60..84
            BASS -> 36..60
            ALTO -> 48..72
            TENOR -> 48..72
        }

    val lowestNote: Note
        get() = Note.fromMidiNumber(noteRange.first)

    val highestNote: Note
        get() = Note.fromMidiNumber(noteRange.last)

    val clefSymbol: String
        get() = when (this) {
            TREBLE -> "\uD834\uDD1E" // 𝄞
            BASS -> "\uD834\uDD22"   // 𝄢
            ALTO, TENOR -> "\uD834\uDD21" // 𝄡
        }

    val symbolYOffset: Float
        get() = when (this) {
            TREBLE -> -0.3f
            BASS -> -0.5f
            ALTO -> 0f
            TENOR -> 0.5f
        }

    fun staffPositionForNote(note: Note): Int {
        val positionFromMiddleC = note.staffPositionFromMiddleC
        return middleCStaffPosition + positionFromMiddleC
    }

    fun isOnLedgerLine(staffPosition: Int): Boolean {
        return staffPosition < 0 || staffPosition > 8
    }

    fun ledgerLinesNeeded(staffPosition: Int): List<Int> {
        val lines = mutableListOf<Int>()

        if (staffPosition < 0) {
            var pos = -2
            while (pos >= staffPosition) {
                if (pos % 2 == 0) {
                    lines.add(pos)
                }
                pos -= 2
            }
        } else if (staffPosition > 8) {
            var pos = 10
            while (pos <= staffPosition) {
                if (pos % 2 == 0) {
                    lines.add(pos)
                }
                pos += 2
            }
        }

        return lines
    }
}
