package com.personal.mikanseta

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.util.AtomicFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var exportContent: String? = null
    private val archive by lazy { AtomicFile(File(filesDir, "Mikanseta/entries.json")) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mikanseta/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "readArchive" -> background(result) {
                    if (!archive.baseFile.exists()) null else archive.openRead().use { it.readBytes().toString(Charsets.UTF_8) }
                }
                "writeArchive" -> background(result) {
                    val content = call.arguments as? String ?: error("缺少备份内容")
                    archive.baseFile.parentFile?.mkdirs()
                    val stream = archive.startWrite()
                    try { stream.write(content.toByteArray(Charsets.UTF_8)); archive.finishWrite(stream) }
                    catch (exception: Exception) { archive.failWrite(stream); throw exception }
                    null
                }
                "appInfo" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success("${info.versionName} ($build)")
                }
                "importArchive", "exportArchive" -> {
                    if (pending != null) { result.error("busy", "请稍后重试", null); return@setMethodCallHandler }
                    val exporting = call.method == "exportArchive"
                    pending = result
                    exportContent = if (exporting) call.arguments as? String else null
                    val intent = Intent(if (exporting) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE).setType("application/json")
                    if (exporting) intent.putExtra(Intent.EXTRA_TITLE, "Mikanseta-backup.json")
                    try { startActivityForResult(intent, if (exporting) 202 else 201) }
                    catch (exception: Exception) { pending = null; exportContent = null; result.error("document", exception.localizedMessage, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try { val value = block(); runOnUiThread { result.success(value) } }
            catch (exception: Exception) { runOnUiThread { result.error("file", exception.localizedMessage, null) } }
        }
    }
    @Deprecated("Android activity result bridge for Flutter")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 201 && requestCode != 202) return
        val result = pending ?: return
        val content = exportContent
        pending = null; exportContent = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(if (requestCode == 202) false else null); return }
        background(result) {
            if (requestCode == 201) {
                contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: error("无法读取文件")
            } else {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write((content ?: error("缺少备份内容")).toByteArray(Charsets.UTF_8)) } ?: error("无法导出文件")
                true
            }
        }
    }
    override fun onDestroy() { io.shutdown(); super.onDestroy() }
}
