package com.kalenwallin.otpsync

import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin
import androidx.compose.runtime.withFrameNanos

@Composable
fun MeshBackground(
    modifier: Modifier = Modifier,
    onPulse: Boolean = false, // Trigger to speed up animation momentarily
    isPaused: Boolean = false, // New: Ability to pause animation
    content: @Composable () -> Unit
) {
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val screenWidth = with(density) { configuration.screenWidthDp.dp.toPx() }
    val screenHeight = with(density) { configuration.screenHeightDp.dp.toPx() }

    // Colors provided by user
    val color1 = Color(0xFF91ACFD)
    val color2 = Color(0xFF607DFE)
    val color3 = Color(0xFFDAFFFD).copy(alpha = 0.61f)
    val baseColor = Color(0xFFB1C2F6) // Fallback/Base background

    // Animation States
    var time by remember { mutableFloatStateOf(0f) }

    // Dynamic Speed Control
    val targetSpeed = when {
        isPaused -> 0f
        onPulse -> 4f
        else -> 1f
    }

    val speed by animateFloatAsState(
        targetValue = targetSpeed,
        animationSpec = tween(durationMillis = 1000, easing = LinearEasing),
        label = "speed"
    )

    // --- Animation Loop ---
    LaunchedEffect(Unit) {
        val startTime = withFrameNanos { it }
        while (true) {
            withFrameNanos { frameTime ->
                if (speed > 0.01f) {
                    time += 0.008f * speed
                }
            }
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(baseColor)
    ) {
        // --- Canvas Drawing ---
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // High performance blur for Android 12+
                        // Using a constant blur effect is cheaper than recreating
                         renderEffect = RenderEffect
                                .createBlurEffect(
                                    80f, 80f, 
                                    Shader.TileMode.MIRROR
                                )
                                .asComposeRenderEffect()
                    } else {
                        alpha = 0.9f // Fallback for older devices
                    }
                }
        ) {
            // Blob 1
            drawCircle(
                color = color1,
                radius = screenWidth * 1.0f,
                center = Offset(
                    x = screenWidth * 0.2f + (cos(time) * screenWidth * 0.3f),
                    y = screenHeight * 0.3f + (sin(time) * screenHeight * 0.2f)
                )
            )

            // Blob 2
            drawCircle(
                color = color2,
                radius = screenWidth * 1.1f,
                center = Offset(
                    x = screenWidth * 0.8f + (cos(time * -0.8f) * screenWidth * 0.3f),
                    y = screenHeight * 0.7f + (sin(time * 0.5f) * screenHeight * 0.2f)
                )
            )

            // Blob 3 (The light one)
            drawCircle(
                color = color3,
                radius = screenWidth * 0.5f,
                center = Offset(
                    x = screenWidth * 0.5f + (sin(time * 1.2f) * screenWidth * 0.2f),
                    y = screenHeight * 0.5f + (cos(time) * screenHeight * 0.2f)
                )
            )
        }

        // Content Overlay
        content()
    }
}
