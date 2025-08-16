package com.example.clipnote_audio

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "clipnote/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        try {
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val displayName = call.argument<String>("displayName")!!
                            val mime = call.argument<String>("mime")!!
                            val subdir = call.argument<String>("subdir") ?: "ClipNote"
                            val uriOrPath = saveToDownloads(bytes, displayName, mime, subdir)
                            result.success(uriOrPath)
                        } catch (e: Exception) {
                            result.error("WRITE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(
        bytes: ByteArray,
        displayName: String,
        mime: String,
        subdir: String
    ): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+：用 MediaStore 寫入公開 Downloads/subdir
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/$subdir")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri: Uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("Insert to MediaStore failed")

            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("OpenOutputStream failed")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)

            uri.toString() // content://... 傳回給 Dart
        } else {
            // Android 9-：直接寫入公開下載資料夾（需要舊權限）
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val folder = File(dir, subdir)
            if (!folder.exists()) folder.mkdirs()
            val outFile = File(folder, displayName)
            FileOutputStream(outFile).use { it.write(bytes) }
            outFile.absolutePath // /storage/emulated/0/Download/ClipNote/xxx
        }
    }
}
