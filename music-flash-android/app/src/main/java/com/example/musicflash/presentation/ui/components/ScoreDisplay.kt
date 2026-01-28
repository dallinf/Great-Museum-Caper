package com.example.musicflash.presentation.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ScoreDisplay(
    correctCount: Int,
    totalAttempts: Int,
    modifier: Modifier = Modifier
) {
    val accuracy = if (totalAttempts > 0) {
        (correctCount.toFloat() / totalAttempts * 100).toInt()
    } else {
        0
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFFF5F5F5))
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(30.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StatItem(
            value = correctCount.toString(),
            label = "Correct",
            valueColor = Color(0xFF4CAF50)
        )

        StatItem(
            value = totalAttempts.toString(),
            label = "Total",
            valueColor = Color.Black
        )

        if (totalAttempts > 0) {
            StatItem(
                value = "$accuracy%",
                label = "Accuracy",
                valueColor = Color(0xFF2196F3)
            )
        }
    }
}

@Composable
private fun StatItem(
    value: String,
    label: String,
    valueColor: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = valueColor
        )
        Text(
            text = label,
            fontSize = 12.sp,
            color = Color.Gray
        )
    }
}
