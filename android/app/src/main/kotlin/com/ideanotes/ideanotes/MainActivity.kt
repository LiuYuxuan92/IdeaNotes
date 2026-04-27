package com.ideanotes.ideanotes

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.ideanotes.app/media_store"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportToDownloads" -> handleExportToDownloads(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleExportToDownloads(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val source = call.argument<String>("source")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType") ?: "application/zip"
        if (source.isNullOrBlank() || displayName.isNullOrBlank()) {
            result.error(
                "INVALID_ARGUMENTS",
                "source / displayName must be provided",
                null,
            )
            return
        }

        try {
            val srcFile = File(source)
            if (!srcFile.exists()) {
                result.error("SOURCE_MISSING", "Source file does not exist: $source", null)
                return
            }

            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                exportViaMediaStore(srcFile, displayName, mimeType)
            } else {
                exportViaPublicDirectory(srcFile, displayName)
            }
            result.success(uri.toString())
        } catch (io: IOException) {
            result.error("IO_ERROR", io.message, null)
        } catch (t: Throwable) {
            result.error("EXPORT_FAILED", t.message, null)
        }
    }

    private fun exportViaMediaStore(srcFile: File, displayName: String, mimeType: String): Uri {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/IdeaNotes",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore insert returned null")

        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IOException("OutputStream null for $uri")
                srcFile.inputStream().use { input ->
                    input.copyTo(out)
                }
            }
        } catch (t: Throwable) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Throwable) {
            }
            throw t
        }

        val finalize = ContentValues().apply {
            put(MediaStore.Downloads.IS_PENDING, 0)
        }
        resolver.update(uri, finalize, null, null)
        return uri
    }

    @Suppress("DEPRECATION")
    private fun exportViaPublicDirectory(srcFile: File, displayName: String): Uri {
        val downloads = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val targetDir = File(downloads, "IdeaNotes")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IOException("Cannot create ${targetDir.absolutePath}")
        }
        val target = File(targetDir, displayName)
        srcFile.inputStream().use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return Uri.fromFile(target)
    }
}
