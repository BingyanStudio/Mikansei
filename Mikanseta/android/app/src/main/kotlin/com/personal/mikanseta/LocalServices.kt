package com.personal.mikanseta

import android.app.*
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.*
import android.content.pm.PackageManager
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.Calendar
import java.util.concurrent.Executors

/** All alarms and widgets use this app's sandbox. No external clock records are changed. */
object LocalServices {
    private const val PREFS = "mikanseta-services-v1"
    const val FIRE = "com.personal.mikanseta.FIRE"
    const val STOP = "com.personal.mikanseta.STOP"
    const val SNOOZE = "com.personal.mikanseta.SNOOZE"
    private const val LIVE = 9101
    fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    fun allowed(c: Context) = manager(c).areNotificationsEnabled() && (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    fun epoch(raw: String?): Long? = try { if (raw.isNullOrBlank() || raw == "null") null else SimpleDateFormat(if(raw.contains(".")) "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" else "yyyy-MM-dd'T'HH:mm:ss'Z'",Locale.US).apply { timeZone=TimeZone.getTimeZone("UTC");isLenient=false }.parse(raw)?.time } catch (_: Exception) { null }
    fun archive(c: Context): JSONObject = JSONObject(File(c.filesDir, "Mikanseta/entries.json").readText())
    private fun signature(archive: JSONObject, e: JSONObject): String? {
        val course = e.optString("courseID").takeIf { it.isNotBlank() && it != "null" }
        val id = course ?: e.optString("entryID")
        val rows = archive.optJSONArray(if (course == null) "entries" else "courses") ?: return null
        val owner = (0 until rows.length()).map { rows.getJSONObject(it) }.firstOrNull { it.optString("id") == id } ?: return null
        if (course == null && (owner.optBoolean("isCompleted") || owner.isNull("reminder"))) return null
        if (course != null && !owner.optBoolean("reminderEnabled")) return null
        val keys = if (course == null) listOf("title","dueDate","plannedStart","plannedEnd","reminder","reminderAnchor","reminderPattern","reminderDelivery","reminderSound","snoozeMinutes","repeatRule","repeatIntervalDays","repeatIntervalMonths","repeatWeekdays","repeatDates","repeatAnchorDate") else listOf("name","weekday","endMinutes","firstDate","lastDate","reminderEnabled","reminderDelivery","reminderSound","snoozeMinutes")
        return keys.joinToString("|") { "$it=${owner.opt(it)}" }
    }
    fun records(c: Context): JSONArray = JSONArray(prefs(c).getString("records", "[]"))
    private fun pending(c: Context, id: String, action: String = FIRE): PendingIntent {
        val intent = Intent(c, ReminderReceiver::class.java).setAction(action).setData(Uri.parse("mikanseta-reminder://$action/${Uri.encode(id)}")).putExtra("id", id)
        return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun open(c: Context, route: JSONObject, key: String): PendingIntent {
        val intent = Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse("mikanseta://route/${Uri.encode(key)}")).putExtra("route", route.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(c, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    // Routes reach MainActivity from an exported component, so only the payload shapes this
    // app builds itself are accepted. Everything else is ignored instead of being parsed.
    private const val ROUTE_QUEUE_LIMIT = 20
    private const val ROUTE_MAX_LENGTH = 1024
    private val ROUTE_KEYS = setOf("url", "entryID", "courseID", "action")
    private val ROUTE_HOSTS = setOf("entry", "focus", "new", "today", "tasks")
    private val ROUTE_ACTIONS = setOf("complete")
    private val ROUTE_KINDS = setOf("task", "homework", "note")
    private val ROUTE_ID = Regex("^[A-Za-z0-9_-]{1,64}$")
    private fun routeURL(raw: String?): String? {
        if (raw.isNullOrBlank() || raw.length > ROUTE_MAX_LENGTH) return null
        // Malformed data from an external Intent must never raise; anything unexpected is ignored.
        return try {
            val uri = Uri.parse(raw)
            if (uri.scheme != "mikanseta") return null
            val host = uri.host ?: return null
            if (!ROUTE_HOSTS.contains(host)) return null
            if (host == "entry" || host == "focus") {
                val segments = uri.pathSegments
                if (segments.size != 1 || !ROUTE_ID.matches(segments[0])) return null
            }
            if ((host == "today" || host == "tasks") && uri.pathSegments.any { it.isNotEmpty() }) return null
            if (host == "new") {
                val kind = uri.getQueryParameter("kind")
                if (kind != null && !ROUTE_KINDS.contains(kind)) return null
            }
            uri.toString()
        } catch (_: Exception) {
            null
        }
    }
    /** Validates a JSON route payload; null means the input must be ignored. */
    fun validRoute(raw: String?): JSONObject? {
        if (raw.isNullOrBlank() || raw.length > ROUTE_MAX_LENGTH) return null
        val route = try { JSONObject(raw) } catch (_: Exception) { return null }
        if (route.length() == 0) return null
        val keys = route.keys()
        while (keys.hasNext()) { val key = keys.next(); if (!ROUTE_KEYS.contains(key) || route.opt(key) !is String) return null }
        val url = route.optString("url").takeIf { it.isNotEmpty() }
        val id = route.optString("entryID").takeIf { it.isNotEmpty() } ?: route.optString("courseID").takeIf { it.isNotEmpty() }
        if ((url == null) == (id == null)) return null
        if (url != null && routeURL(url) == null) return null
        if (id != null && !ROUTE_ID.matches(id)) return null
        val action = route.optString("action").takeIf { it.isNotEmpty() }
        if (action != null && !ROUTE_ACTIONS.contains(action)) return null
        return route
    }
    /** Validates an intent data URI and turns it into the route payload Dart already reads. */
    fun routeFromData(data: Uri?): JSONObject? {
        if (data == null || data.scheme != "mikanseta") return null
        return routeURL(data.toString())?.let { JSONObject().put("url", it) }
    }
    @Synchronized fun queueRoute(c: Context, route: JSONObject) {
        val current = try { JSONArray(prefs(c).getString("routes", "[]")) } catch (_: Exception) { JSONArray() }
        current.put(route)
        while (current.length() > ROUTE_QUEUE_LIMIT) current.remove(0)
        prefs(c).edit().putString("routes", current.toString()).commit()
    }
    @Synchronized fun takeRoutes(c: Context): List<Map<String, String>> {
        val rows = try { JSONArray(prefs(c).getString("routes", "[]")) } catch (_: Exception) { JSONArray() }
        prefs(c).edit().remove("routes").commit()
        val routes = mutableListOf<Map<String, String>>()
        for (index in 0 until rows.length()) {
            val route = rows.optJSONObject(index) ?: continue
            val row = linkedMapOf<String, String>()
            val keys = route.keys()
            while (keys.hasNext()) { val key = keys.next(); val value = route.opt(key); if (value is String) row[key] = value }
            if (row.isNotEmpty()) routes.add(row)
        }
        return routes
    }
    private fun schedule(c: Context, event: JSONObject): Boolean {
        if (!allowed(c)) return false
        val at = event.optLong("trigger", event.getLong("at")); if (at <= System.currentTimeMillis()) return false
        val alarm = c.getSystemService(AlarmManager::class.java)
        val intent = pending(c, event.getString("id"))
        if (event.optString("delivery") == "alarm") {
            if (!exact(c)) return false
            alarm.setAlarmClock(AlarmManager.AlarmClockInfo(at, open(c, route(event), "alarm-${event.getString("id")}")), intent)
        } else if (exact(c)) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        return true
    }
    @Synchronized fun reconcile(c: Context, args: Map<*, *>): Map<String, Any> {
        channels(c)
        val root = JSONObject(args["archive"] as String)
        val desired = JSONArray(args["plan"] as? List<*> ?: emptyList<Any>())
        val active = manager(c).activeNotifications.mapNotNull { it.tag }.toSet()
        val next = linkedMapOf<String, JSONObject>()
        for (i in 0 until desired.length()) {
            val event = desired.getJSONObject(i); val signature = signature(root, event) ?: continue
            event.put("signature", signature); next[event.getString("id")] = event
        }
        val old = records(c)
        for (i in 0 until old.length()) {
            val event = old.getJSONObject(i); val id = event.getString("id")
            val valid = signature(root, event) == event.optString("signature")
            val snoozed = event.optLong("trigger") > System.currentTimeMillis()
            if (valid && (snoozed || active.contains(id) || RingingService.activeID==id)) {
                if (snoozed || !next.containsKey(id)) next[id] = event
            } else if (!valid || !next.containsKey(id)) {
                c.getSystemService(AlarmManager::class.java).cancel(pending(c,id)); manager(c).cancel(id, 2001)
                if (RingingService.activeID == id) c.stopService(Intent(c,RingingService::class.java))
            }
        }
        prefs(c).edit().putString("records", JSONArray(next.values.toList()).toString())
            .putString("summary", JSONObject(args["summary"] as? Map<*, *> ?: emptyMap<String,Any>()).toString())
            .putBoolean("live", args["liveEnabled"] == true).commit()
        var scheduled = 0
        next.values.forEach { if (schedule(c,it)) scheduled++ }
        prefs(c).edit().putInt("scheduled",scheduled).apply()
        refreshWidgets(c); live(c)
        return status(c)
    }
    fun restore(c: Context) { channels(c); val rows=records(c); for(i in 0 until rows.length()) { val e=rows.getJSONObject(i); if (signature(archive(c),e)==e.optString("signature")) schedule(c,e) }; refreshWidgets(c); live(c) }
    fun status(c: Context): Map<String, Any> = mapOf("notification" to if(allowed(c)) "已开启" else "未开启", "alarm" to if(exact(c)) "精确提醒已允许" else "未允许精确闹钟", "scheduled" to prefs(c).getInt("scheduled",0), "error" to if(!exact(c)) "闹钟式提醒尚未安排，弹窗可能延迟；请开启闹钟权限。" else "", "live" to if(prefs(c).getBoolean("live",false)) "今日 DDL 常驻通知已开启" else "未开启")
    fun route(e: JSONObject): JSONObject = JSONObject().apply { val course=e.optString("courseID"); if(course.isNotBlank() && course!="null") put("courseID",course) else put("entryID",e.optString("entryID")) }
    fun sound(c: Context, value: String): Uri = when(value) {
        "morning","chime","pulse" -> Uri.parse("android.resource://${c.packageName}/raw/mikansei_$value")
        else -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
    }
    fun channels(c: Context) {
        if(Build.VERSION.SDK_INT < 26) return
        for(delivery in listOf("popup","alarm")) for(tone in listOf("system","morning","chime","pulse")) {
            val ch=NotificationChannel("reminder-$delivery-$tone-v1", "${if(delivery=="alarm") "闹钟" else "弹窗"} · $tone",NotificationManager.IMPORTANCE_HIGH)
            val uri=if(tone=="system"&&delivery=="popup") RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) else sound(c,tone)
            ch.setSound(if(delivery=="alarm") null else uri,AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            ch.enableVibration(true);manager(c).createNotificationChannel(ch)
        }
        manager(c).createNotificationChannel(NotificationChannel("deadline-live-v1","今日 DDL",NotificationManager.IMPORTANCE_LOW))
    }
    fun notification(c: Context,e: JSONObject,ringing: Boolean): Notification {
        val tone=e.optString("sound","system");val channel="reminder-${if(ringing)"alarm" else "popup"}-$tone-v1"
        val b=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,channel) else Notification.Builder(c)
        val id=e.getString("id")
        b.setSmallIcon(android.R.drawable.ic_menu_agenda).setContentTitle(e.optString("title")).setContentText(e.optString("body"))
            .setStyle(Notification.BigTextStyle().bigText(e.optString("body"))).setContentIntent(open(c,route(e),id))
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(if(ringing) Notification.CATEGORY_ALARM else Notification.CATEGORY_REMINDER)
            .setAutoCancel(!ringing).setOngoing(ringing).setPriority(Notification.PRIORITY_HIGH)
            .addAction(Notification.Action.Builder(null,"稍后提醒",pending(c,id,SNOOZE)).build())
            .addAction(Notification.Action.Builder(null,"停止",pending(c,id,STOP)).build())
        if(!e.isNull("entryID")) b.addAction(Notification.Action.Builder(null,"标为完成",open(c,route(e).put("action","complete"),"complete-$id")).build())
        if(ringing && (Build.VERSION.SDK_INT<34 || manager(c).canUseFullScreenIntent())) {
            val intent=Intent(c,AlarmScreen::class.java).setData(Uri.parse("mikanseta-alarm://${Uri.encode(id)}")).putExtra("event",e.toString())
            b.setFullScreenIntent(PendingIntent.getActivity(c,0,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),true)
        }
        return b.build()
    }
    @Synchronized fun fire(c: Context,id: String) {
        val list=records(c);val event=(0 until list.length()).map{list.getJSONObject(it)}.firstOrNull{it.optString("id")==id}?:return
        if(signature(archive(c),event)!=event.optString("signature")||!allowed(c))return
        if(event.optString("delivery")=="alarm") {
            try {val intent=Intent(c,RingingService::class.java).putExtra("event",event.toString()); if(Build.VERSION.SDK_INT>=26)c.startForegroundService(intent) else c.startService(intent)}
            // Android 12+ may refuse a foreground start from the background. The ringing service
            // covers failures raised inside onStartCommand; this covers the rejected start call.
            catch(e:Exception) {android.util.Log.e("Mikanseta","Foreground alarm start rejected",e);manager(c).notify(id,2001,notification(c,event,false))}
        } else manager(c).notify(id,2001,notification(c,event,false))
    }
    @Synchronized fun action(c: Context,id: String,snooze: Boolean) {
        manager(c).cancel(id,2001);if(RingingService.activeID==id)c.stopService(Intent(c,RingingService::class.java))
        val list=records(c);val next=JSONArray()
        for(i in 0 until list.length()){val e=list.getJSONObject(i);if(e.optString("id")==id){if(snooze && signature(archive(c),e)==e.optString("signature")){e.put("trigger",System.currentTimeMillis()+e.optInt("snoozeMinutes",5)*60000L);next.put(e);schedule(c,e)}else c.getSystemService(AlarmManager::class.java).cancel(pending(c,id))}else next.put(e)}
        prefs(c).edit().putString("records",next.toString()).commit()
    }
    fun live(c: Context) {
        if(!prefs(c).getBoolean("live",false)||!allowed(c)){manager(c).cancel(LIVE);return}
        val summary=JSONObject(prefs(c).getString("summary","{}"));val items=summary.optJSONArray("liveItems")?:JSONArray()
        if(items.length()==0 || summary.optLong("dayEnd") <= System.currentTimeMillis()){manager(c).cancel(LIVE);return}
        val first=items.getJSONObject(0);val deadline=first.optLong("deadline",0)
        val text=(1 until items.length()).joinToString("\n"){items.getJSONObject(it).optString("title")}+"\n${summary.optInt("liveCount")} 件未完成"
        val b=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,"deadline-live-v1") else Notification.Builder(c)
        b.setSmallIcon(android.R.drawable.ic_menu_my_calendar).setContentTitle(first.optString("title")).setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open(c,JSONObject().put("entryID",first.optString("id")),"live"))
            .setOnlyAlertOnce(true).setOngoing(true).setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_STATUS)
        if(deadline>System.currentTimeMillis()) b.setWhen(deadline).setUsesChronometer(true).setChronometerCountDown(true)
        else b.setSubText(if(deadline>0) "已到期" else "无时限")
        manager(c).notify(LIVE,b.build())
    }
    fun refreshWidgets(c: Context) { for(type in arrayOf(ChecklistWidget::class.java,QuickAddWidget::class.java,ProgressWidget::class.java,FocusWidget::class.java)){val ids=AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c,type));updateWidgets(c,ids,type.simpleName)} }
    fun updateWidgets(c: Context,ids: IntArray,mode: String) {
        val root=try{archive(c)}catch(_:Exception){JSONObject()};val entries=root.optJSONArray("entries")?:JSONArray();val rows=(0 until entries.length()).map{entries.getJSONObject(it)}
        val open=rows.filter{it.optString("kind")!="note"&&!it.optBoolean("isCompleted")}.sortedWith(compareByDescending<JSONObject>{it.optInt("priority")}.thenBy{epoch(it.optString(if(it.optString("kind")=="schedule")"plannedStart" else "dueDate"))?:Long.MAX_VALUE})
        fun dateKey(ms:Long)=Calendar.getInstance().apply{timeInMillis=ms}.let{"${it.get(Calendar.YEAR)}-${it.get(Calendar.DAY_OF_YEAR)}"}
        val today=dateKey(System.currentTimeMillis());val done=rows.count{it.optBoolean("isCompleted")&&epoch(it.optString("completedAt"))?.let{ms->dateKey(ms)==today}==true}
        for(id in ids) {
            val v=RemoteViews(c.packageName,R.layout.mikanseta_widget)
            v.setTextViewText(R.id.widget_title,when(mode){"QuickAddWidget"->"快速记下";"ProgressWidget"->"今日进度";"FocusWidget"->"正在做";else->"待办清单"})
            v.setViewVisibility(R.id.widget_timer,android.view.View.GONE)
            v.setViewVisibility(R.id.widget_focus_action,android.view.View.GONE)
            v.setViewVisibility(R.id.widget_quick,if(mode=="QuickAddWidget")android.view.View.VISIBLE else android.view.View.GONE)
            for(pair in listOf(R.id.widget_task to "task",R.id.widget_homework to "homework",R.id.widget_note to "note")) v.setOnClickPendingIntent(pair.first,open(c,JSONObject().put("url","mikanseta://new?kind=${pair.second}"),"quick-$id-${pair.second}"))
            val focus=open.firstOrNull{!it.isNull("startedAt")} ?: open.filter{it.optDouble("elapsedSeconds",0.0)>0}.maxByOrNull{epoch(it.optString("updatedAt"))?:0L}
            val body=when(mode){"QuickAddWidget"->"待办 · 作业 · 笔记\n一句话，先记下来";"ProgressWidget"->"今日完成 $done 件\n还有 ${open.size} 件待办";"FocusWidget"->focus?.optString("title")?:"暂未开始专注";else->open.take(5).joinToString("\n"){"□ ${it.optString("title")}"}.ifEmpty{"暂无未完成事项"}}
            v.setTextViewText(R.id.widget_body,body)
            val route=if(mode=="QuickAddWidget")"mikanseta://new?kind=task" else if(mode=="FocusWidget"&&focus!=null)"mikanseta://entry/${focus.optString("id")}" else "mikanseta://tasks"
            v.setOnClickPendingIntent(R.id.widget_body,open(c,JSONObject().put("url",route),"widget-$id"))
            v.setOnClickPendingIntent(R.id.widget_title,open(c,JSONObject().put("url","mikanseta://today"),"widget-title-$id"))
            v.setOnClickPendingIntent(R.id.widget_add,open(c,JSONObject().put("url","mikanseta://new?kind=task"),"widget-add-$id"))
            if(mode=="FocusWidget"&&focus!=null){val started=epoch(focus.optString("startedAt"));val elapsed=focus.optDouble("elapsedSeconds",0.0)*1000;val base=SystemClock.elapsedRealtime()-(if(started!=null)System.currentTimeMillis()-started else 0)-elapsed.toLong();v.setViewVisibility(R.id.widget_timer,android.view.View.VISIBLE);v.setChronometer(R.id.widget_timer,base,"%s",started!=null);v.setViewVisibility(R.id.widget_focus_action,android.view.View.VISIBLE);v.setTextViewText(R.id.widget_focus_action,if(started!=null)"暂停" else "继续");v.setOnClickPendingIntent(R.id.widget_focus_action,open(c,JSONObject().put("url","mikanseta://focus/${focus.optString("id")}?action=${if(started!=null)"pause" else "start"}"),"focus-$id"))}
            AppWidgetManager.getInstance(c).updateAppWidget(id,v)
        }
    }
}
class ReminderReceiver:BroadcastReceiver(){override fun onReceive(context:Context,intent:Intent){val pending=goAsync();val worker=Executors.newSingleThreadExecutor();worker.execute{try{val id=intent.getStringExtra("id")?:"";when(intent.action){LocalServices.FIRE->LocalServices.fire(context,id);LocalServices.STOP->LocalServices.action(context,id,false);LocalServices.SNOOZE->LocalServices.action(context,id,true);else->LocalServices.restore(context)}}catch(e:Exception){android.util.Log.e("Mikanseta","Reminder update failed",e)}finally{pending.finish();worker.shutdown()}}}}
class RingingService:Service(){
 companion object{@Volatile var activeID:String?=null}
 private var player:MediaPlayer?=null;private val handler=Handler(Looper.getMainLooper())
 override fun onBind(intent:Intent?)=null
 override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int{
   // A background start through startForegroundService owns a system deadline: this call must
   // reach startForeground() or stop the service, otherwise the system turns the timeout into a
   // crash. An unusable intent is therefore ended here instead of returning early.
   val event=try{intent?.getStringExtra("event")?.takeIf{it.isNotBlank()}?.let{JSONObject(it)}}catch(e:Exception){android.util.Log.e("Mikanseta","Alarm event unreadable",e);null}
   val id=event?.optString("id")?.takeIf{it.isNotBlank()}
   if(event==null||id==null){android.util.Log.e("Mikanseta","Alarm start ignored: missing event payload");stopSelf(startId);return START_NOT_STICKY}
   try{
     LocalServices.channels(this)
     // Android 12+ can refuse the promotion (background start restrictions) and Android 14 can
     // reject the notification itself; both arrive as runtime exceptions inside onStartCommand.
     startForeground(9102,LocalServices.notification(this,event,true))
     activeID=id
     player?.release()
     try{player=MediaPlayer().apply{setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());setDataSource(this@RingingService,LocalServices.sound(this@RingingService,event.optString("sound")));isLooping=true;prepare();start()}}catch(e:Exception){android.util.Log.e("Mikanseta","Alarm sound unavailable",e)}
     handler.removeCallbacksAndMessages(null);handler.postDelayed({stopSelf()},5*60*1000L)
   }catch(e:Exception){
     // Foreground delivery is unavailable: keep the reminder as a normal notification so the user
     // still sees it, and never let the exception escape into the main looper.
     android.util.Log.e("Mikanseta","Foreground alarm unavailable",e)
     try{LocalServices.manager(this).notify(id,2001,LocalServices.notification(this,event,false))}
     catch(inner:Exception){android.util.Log.e("Mikanseta","Alarm fallback notification unavailable",inner)}
     activeID=null
     stopSelf(startId)
   }
   return START_NOT_STICKY
 }
 override fun onDestroy(){handler.removeCallbacksAndMessages(null);player?.release();player=null;activeID=null;super.onDestroy()}
}
class AlarmScreen:Activity(){override fun onCreate(state:Bundle?){super.onCreate(state);if(Build.VERSION.SDK_INT>=27){setShowWhenLocked(true);setTurnScreenOn(true)};val event=JSONObject(intent.getStringExtra("event")?:"{}");val box=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(40,100,40,40);setBackgroundColor(0xfff5edde.toInt())};box.addView(TextView(this).apply{text=event.optString("title");textSize=28f;setTextColor(0xff38291e.toInt())});for(pair in listOf("稍后提醒" to true,"停止" to false)){box.addView(Button(this).apply{text=pair.first;setOnClickListener{LocalServices.action(this@AlarmScreen,event.getString("id"),pair.second);finish()}})};setContentView(box)}}
open class BaseWidget:AppWidgetProvider(){override fun onUpdate(c:Context,m:AppWidgetManager,ids:IntArray){LocalServices.updateWidgets(c,ids,javaClass.simpleName)}}
class ChecklistWidget:BaseWidget()
class QuickAddWidget:BaseWidget()
class ProgressWidget:BaseWidget()
class FocusWidget:BaseWidget()
