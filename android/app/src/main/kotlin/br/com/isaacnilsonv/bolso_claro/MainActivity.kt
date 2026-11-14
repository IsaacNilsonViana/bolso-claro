package br.com.isaacnilsonv.bolso_claro

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.content.FileProvider
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ocrExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bolso_claro/files").setMethodCallHandler { call, result ->
            if (call.method == "attachmentDirectory") { result.success(File(filesDir, "anexos").absolutePath); return@setMethodCallHandler }
            if (call.method != "open" && call.method != "delete" && call.method != "recognize") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val path = call.argument<String>("path") ?: error("Arquivo ausente")
                val file = File(path)
                if (!file.isFile || !file.canonicalPath.startsWith(filesDir.canonicalPath + File.separator)) error("Arquivo inválido")
                if (call.method == "delete") { result.success(file.delete()); return@setMethodCallHandler }
                if (call.method == "recognize") {
                    ocrExecutor.execute {
                        try {
                            val text = recognize(file)
                            runOnUiThread { result.success(text) }
                        } catch (e: Exception) {
                            Log.e("BolsoClaroOCR", "Recognition failed", e)
                            runOnUiThread { result.error("OCR_FAILED", e.message, null) }
                        }
                    }
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                val mime = when (file.extension.lowercase()) { "pdf" -> "application/pdf"; "png" -> "image/png"; "webp" -> "image/webp"; else -> "image/jpeg" }
                startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Abrir anexo"))
                result.success(null)
            } catch (e: Exception) { result.error("OPEN_FAILED", e.message, null) }
        }
    }

    private fun recognize(file: File): String {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            if (file.extension.lowercase() != "pdf") {
                val image = InputImage.fromFilePath(this, Uri.fromFile(file))
                return Tasks.await(recognizer.process(image)).text
            }
            val output = StringBuilder()
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    for (index in 0 until minOf(renderer.pageCount, 5)) {
                        renderer.openPage(index).use { page ->
                            val scale = minOf(3f, 2200f / maxOf(page.width, page.height))
                            val bitmap = Bitmap.createBitmap(
                                (page.width * scale).toInt(),
                                (page.height * scale).toInt(),
                                Bitmap.Config.ARGB_8888
                            )
                            try {
                                bitmap.eraseColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                if (output.isNotEmpty()) output.append('\n')
                                output.append(Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0))).text)
                            } finally {
                                bitmap.recycle()
                            }
                        }
                    }
                }
            }
            return output.toString()
        } finally {
            recognizer.close()
        }
    }

    override fun onDestroy() {
        ocrExecutor.shutdown()
        super.onDestroy()
    }
}
