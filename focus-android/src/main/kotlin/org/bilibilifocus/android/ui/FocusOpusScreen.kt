package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusOpusViewModel
import org.bilibilifocus.android.OpusUiState
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.OpusImage
import org.bilibilifocus.core.model.OpusTextNode
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.OpusService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusOpusScreen(
    opusId: String,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
) {
    val viewModel = remember(opusId) {
        FocusOpusViewModel(
            service = OpusService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            )
        )
    }

    LaunchedEffect(opusId) {
        viewModel.load(opusId)
    }

    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    val author = (state as? OpusUiState.Loaded)?.detail?.author?.name ?: "帖子"
                    Text(author, maxLines = 1)
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
    ) { innerPadding ->
        when (val s = state) {
            OpusUiState.Idle, OpusUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is OpusUiState.Failed -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    Text(s.message, style = MaterialTheme.typography.bodyMedium)
                }
            }

            OpusUiState.LoginRequired -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    Text("需要登录才能查看", style = MaterialTheme.typography.bodyMedium)
                }
            }

            is OpusUiState.Loaded -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    s.detail.paragraphs.forEachIndexed { index, para ->
                        item(key = "para-$index") {
                            OpusParagraphView(paragraph = para)
                        }
                    }

                    item { Box(modifier = Modifier.padding(top = 32.dp)) }
                }
            }
        }
    }
}

@Composable
private fun OpusParagraphView(paragraph: OpusDetail.Paragraph) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        paragraph.blocks.forEachIndexed { _, block ->
            when (block) {
                is OpusBlock.Text -> OpusRichText(nodes = block.nodes)
                is OpusBlock.Image -> OpusImageGrid(images = block.pics)
                is OpusBlock.Code -> OpusCodeBlock(lang = block.lang, content = block.content)
            }
        }
    }
}

@Composable
private fun OpusRichText(nodes: List<OpusTextNode>) {
    val annotatedString = buildAnnotatedString {
        nodes.forEach { node ->
            if (node.emojiUrl != null) {
                append("[表情]")
            } else {
                val style = if (node.bold) {
                    SpanStyle(fontWeight = FontWeight.Bold)
                } else {
                    SpanStyle()
                }
                withStyle(style) {
                    append(node.text)
                }
            }
        }
    }
    Text(
        text = annotatedString,
        style = MaterialTheme.typography.bodyMedium,
    )
}

@Composable
private fun OpusImageGrid(images: List<OpusImage>) {
    val columnCount = if (images.size == 1) 1 else 2
    val rows = images.chunked(columnCount)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { rowImages ->
            androidx.compose.foundation.layout.Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                rowImages.forEach { image ->
                    val imageHeight = if (images.size == 1) 220 else 160
                    AsyncImage(
                        model = ImageRequest.Builder(LocalContext.current)
                            .data(image.url)
                            .crossfade(true)
                            .build(),
                        contentDescription = null,
                        modifier = Modifier
                            .weight(1f)
                            .height(imageHeight.dp)
                            .clip(RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Crop,
                    )
                }
                repeat(columnCount - rowImages.size) {
                    androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun OpusCodeBlock(lang: String, content: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .padding(12.dp),
    ) {
        Text(
            text = content,
            style = MaterialTheme.typography.bodySmall.copy(fontStyle = FontStyle.Italic),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
