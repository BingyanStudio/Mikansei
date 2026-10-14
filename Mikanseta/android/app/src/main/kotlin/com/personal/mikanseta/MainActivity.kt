package com.personal.mikanseta

import android.app.Activity
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.content.ContentUris
import android.os.Build
import android.provider.CalendarContract
import android.provider.AlarmClock
import android.util.AtomicFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.util.concurrent.Executors
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var exportContent: String? = null
    private var calendarPermission: MethodChannel.Result? = null
    private val calendarDeviceID by lazy {
        // Calendar provider IDs belong to this installation. Android backup must
        // not restore this identity onto another phone with unrelated calendars.
        val file = File(noBackupFilesDir, "calendar-installation-id")
        if (file.exists()) file.readText().trim()
        else UUID.randomUUID().toString().also { file.writeText(it) }
    }
    private val archive by lazy { AtomicFile(File(filesDir, "Mikanseta/entries.json")) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mikanseta/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "calendarDeviceID" -> result.success(calendarDeviceID)
                "calendarAccess" -> result.success(checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED)
                "requestCalendarAccess" -> {
                    if (checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (calendarPermission != null) result.error("busy", "正在等待日历授权", null)
                    else {
                        calendarPermission = result
                        requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), 301)
                    }
                }
                "calendarSources" -> background(result) { calendarSources() }
                "calendarEvents" -> background(result) {
                    val args = call.arguments as Map<*, *>
                    calendarEvents(args)
                }
                "openCalendarEvent", "addCalendarEvent", "createClockAlarm", "createClockTimer", "showClock" -> {
                    try {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val intent = when (call.method) {
                            "openCalendarEvent" -> Intent(Intent.ACTION_VIEW, ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, (args["eventID"] as String).toLong())).apply {
                                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, (args["start"] as Number).toLong())
                                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, (args["end"] as Number).toLong())
                            }
                            "addCalendarEvent" -> Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                                val begin = (args["start"] as Number).toLong()
                                val end = (args["end"] as Number).toLong()
                                require(end > begin) { "结束时间必须晚于开始时间" }
                                putExtra(CalendarContract.Events.TITLE, args["title"] as String)
                                putExtra(CalendarContract.Events.DESCRIPTION, args["body"] as String)
                                putExtra(CalendarContract.Events.EVENT_LOCATION, args["location"] as String)
                                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                                putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, args["allDay"] as Boolean)
                            }
                            "createClockAlarm" -> Intent(AlarmClock.ACTION_SET_ALARM).apply {
                                val hour = (args["hour"] as Number).toInt()
                                val minute = (args["minute"] as Number).toInt()
                                require(hour in 0..23 && minute in 0..59)
                                putExtra(AlarmClock.EXTRA_HOUR, hour)
                                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                                putExtra(AlarmClock.EXTRA_MESSAGE, args["title"] as String)
                                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            "createClockTimer" -> Intent(AlarmClock.ACTION_SET_TIMER).apply {
                                val seconds = (args["seconds"] as Number).toInt()
                                require(seconds in 1..86400)
                                putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                                putExtra(AlarmClock.EXTRA_MESSAGE, args["title"] as String)
                                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            else -> Intent(AlarmClock.ACTION_SHOW_ALARMS)
                        }
                        val handler = intent.resolveActivity(packageManager)
                        if (handler == null) result.error("unavailable", "未找到可处理此操作的系统日历或时钟应用", null)
                        else {
                            // AOSP's Kotlin EventInfoActivity casts the normal URI's last String
                            // segment to Long. Its explicitly supported EventTime route parses
                            // the ID and times correctly. Other calendar apps keep the standard URI.
                            if (call.method == "openCalendarEvent" && handler.packageName == "com.android.calendar" && handler.className == "com.android.calendar.EventInfoActivity") {
                                intent.data = intent.data!!.buildUpon().appendPath("EventTime")
                                    .appendPath((args["start"] as Number).toLong().toString())
                                    .appendPath((args["end"] as Number).toLong().toString()).build()
                                intent.component = handler
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (error: Exception) { result.error("system_app", error.localizedMessage, null) }
                }
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
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 301) {
            calendarPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            calendarPermission = null
        }
    }
    private fun calendarSources(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        contentResolver.query(CalendarContract.Calendars.CONTENT_URI, arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.CALENDAR_COLOR), null, null, null)?.use { rows ->
            while (rows.moveToNext()) result.add(mapOf("id" to rows.getLong(0).toString(), "title" to rows.getString(1), "account" to rows.getString(2), "color" to rows.getInt(3)))
        }
        return result
    }
    private fun calendarEvents(args: Map<*, *>): List<Map<String, Any?>> {
        val ids = (args["selected"] as List<*>).map { (it as String).toLong().toString() }
        require(ids.size <= 100)
        if (ids.isEmpty()) return emptyList()
        val start = (args["start"] as Number).toLong()
        val end = (args["end"] as Number).toLong()
        require(end > start && end - start <= 32L * 86400000L)
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, start); ContentUris.appendId(it, end)
        }.build()
        val fields = arrayOf("event_id", "calendar_id", "title", "description", "eventLocation", "begin", "end", "allDay", "calendar_displayName", "rrule", "original_id", "originalInstanceTime")
        val result = mutableListOf<Map<String, Any?>>()
        contentResolver.query(uri, fields, "calendar_id IN (${ids.joinToString(",") { "?" }}) AND (eventStatus IS NULL OR eventStatus != 2)", ids.toTypedArray(), "begin ASC")?.use { rows ->
            while (rows.moveToNext()) {
                val eventID = rows.getLong(0).toString()
                val recurring = !rows.isNull(9) && !rows.getString(9).isNullOrBlank() || !rows.isNull(10)
                val master = if (rows.isNull(10)) eventID else rows.getLong(10).toString()
                val occurrence = if (recurring) (if (rows.isNull(11)) rows.getLong(5) else rows.getLong(11)).toString() else "single"
                result.add(mapOf("key" to "${rows.getLong(1)}/$master/$occurrence", "eventID" to eventID, "calendarID" to rows.getLong(1).toString(), "title" to (rows.getString(2) ?: "未命名日程"), "body" to (rows.getString(3) ?: ""), "location" to (rows.getString(4) ?: ""), "start" to rows.getLong(5), "end" to rows.getLong(6), "allDay" to (rows.getInt(7) != 0), "calendarTitle" to (rows.getString(8) ?: "日历")))
                check(result.size <= 10000) { "所选日历事件过多，请减少来源后重试" }
            }
        }
        return result
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
