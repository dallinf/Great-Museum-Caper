package com.example.musicflash.presentation.ui

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.example.musicflash.presentation.ui.screen.PracticeScreen
import com.example.musicflash.presentation.ui.theme.MusicFlashTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalPermissionsApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MusicFlashTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val permissionState = rememberPermissionState(
                        Manifest.permission.RECORD_AUDIO
                    )

                    PracticeScreen(
                        onRequestPermission = {
                            if (!permissionState.status.isGranted) {
                                permissionState.launchPermissionRequest()
                            }
                        }
                    )
                }
            }
        }
    }
}
