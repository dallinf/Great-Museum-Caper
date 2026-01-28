package com.example.musicflash.domain.model

enum class Pitch(val semitone: Int) {
    C(0),
    D(2),
    E(4),
    F(5),
    G(7),
    A(9),
    B(11);

    val staffPosition: Int
        get() = when (this) {
            C -> 0
            D -> 1
            E -> 2
            F -> 3
            G -> 4
            A -> 5
            B -> 6
        }

    companion object {
        fun fromSemitone(semitone: Int): Pitch? =
            entries.find { it.semitone == semitone }
    }
}
