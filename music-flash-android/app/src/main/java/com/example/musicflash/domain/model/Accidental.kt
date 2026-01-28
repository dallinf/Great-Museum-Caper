package com.example.musicflash.domain.model

enum class Accidental(val symbol: String, val semitoneOffset: Int) {
    SHARP("\u266F", 1),
    FLAT("\u266D", -1),
    NATURAL("\u266E", 0)
}
