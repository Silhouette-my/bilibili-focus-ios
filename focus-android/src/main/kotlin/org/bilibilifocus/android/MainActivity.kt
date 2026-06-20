package org.bilibilifocus.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            BilibiliFocusTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    FocusApp()
                }
            }
        }
    }
}
