package com.example.musicflash.audio

import be.tarsos.dsp.AudioDispatcher
import be.tarsos.dsp.io.jvm.AudioDispatcherFactory
import be.tarsos.dsp.pitch.PitchDetectionHandler
import be.tarsos.dsp.pitch.PitchProcessor
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

data class PitchData(
    val frequency: Float,
    val amplitude: Float
)

class PitchDetector {
    private var dispatcher: AudioDispatcher? = null
    private var audioThread: Thread? = null

    private val sampleRate = 44100f
    private val bufferSize = 2048
    private val bufferOverlap = 0
    private val amplitudeThreshold = 0.2f

    var isRunning: Boolean = false
        private set

    fun startDetection(): Flow<PitchData> = callbackFlow {
        if (isRunning) {
            close()
            return@callbackFlow
        }

        try {
            dispatcher = AudioDispatcherFactory.fromDefaultMicrophone(
                sampleRate.toInt(),
                bufferSize,
                bufferOverlap
            )

            val pitchHandler = PitchDetectionHandler { result, audioEvent ->
                val pitch = result.pitch
                val amplitude = audioEvent.rms.toFloat()

                if (pitch > 0 && amplitude > amplitudeThreshold && pitch > 20 && pitch < 5000) {
                    trySend(PitchData(pitch, amplitude))
                } else if (amplitude > 0) {
                    // Send amplitude even when no pitch detected (for meter)
                    trySend(PitchData(-1f, amplitude))
                }
            }

            val pitchProcessor = PitchProcessor(
                PitchProcessor.PitchEstimationAlgorithm.YIN,
                sampleRate,
                bufferSize,
                pitchHandler
            )

            dispatcher?.addAudioProcessor(pitchProcessor)

            audioThread = Thread(dispatcher, "Audio Thread")
            audioThread?.start()
            isRunning = true

            awaitClose {
                stopDetection()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            close(e)
        }
    }

    fun stopDetection() {
        isRunning = false
        dispatcher?.stop()
        dispatcher = null
        audioThread?.interrupt()
        audioThread = null
    }
}
