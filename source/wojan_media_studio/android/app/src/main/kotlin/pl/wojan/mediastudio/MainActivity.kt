package pl.wojan.mediastudio

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "pl.wojan.mediastudio/native"
    private val pendingShared = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "freeSpace" -> {
                        val st = StatFs(call.argument<String>("path") ?: filesDir.path)
                        result.success(st.availableBytes)
                    }
                    "saveToMediaStore" -> result.success(saveToMediaStore(call.argument<String>("path")!!, call.argument<String>("mime")!!, call.argument<String>("name")!!))
                    "shareTargets" -> {
                        val i = Intent(Intent.ACTION_SEND).setType(call.argument<String>("mime") ?: "video/*")
                        val list = packageManager.queryIntentActivities(i, 0).map {
                            mapOf("package" to it.activityInfo.packageName, "label" to it.loadLabel(packageManager).toString())
                        }.distinctBy { it["package"] }
                        result.success(list)
                    }
                    "shareToPackage" -> {
                        val uri = uriFor(File(call.argument<String>("path")!!))
                        val i = Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: "video/mp4"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            call.argument<String>("text")?.let { putExtra(Intent.EXTRA_TEXT, it) }
                            setPackage(call.argument<String>("package"))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (i.resolveActivity(packageManager) != null) {
                            startActivity(i); result.success(true)
                        } else result.success(false)
                    }
                    "installApk" -> {
                        val f = File(call.argument<String>("path")!!)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(false)
                        } else {
                            // Official system installer – user confirms the update.
                            val i = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uriFor(f), "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(i); result.success(true)
                        }
                    }
                    "setRingtone" -> {
                        if (!Settings.System.canWrite(this)) {
                            startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(false)
                        } else {
                            val path = call.argument<String>("path")!!
                            val type = if (call.argument<String>("type") == "notification") RingtoneManager.TYPE_NOTIFICATION else RingtoneManager.TYPE_RINGTONE
                            val uri = saveToMediaStore(path, "audio/mpeg", File(path).name, ringtone = true)
                            if (uri != null) { RingtoneManager.setActualDefaultRingtoneUri(this, type, Uri.parse(uri)); result.success(true) } else result.success(false)
                        }
                    }
                    "isUnmetered" -> {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                        result.success(caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true)
                    }
                    "isPowerSaveOrHot" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val hot = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && pm.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE
                        result.success(pm.isPowerSaveMode || hot)
                    }
                    "takeSharedFiles" -> { result.success(pendingShared.toList()); pendingShared.clear() }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun uriFor(f: File): Uri = FileProvider.getUriForFile(this, "$packageName.files", f)

    /** Copies incoming shared content URIs into app cache so Dart can read them. */
    private fun handleIntent(i: Intent?) {
        if (i == null) return
        val uris = mutableListOf<Uri>()
        when (i.action) {
            Intent.ACTION_SEND -> (if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM))?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else @Suppress("DEPRECATION") i.getParcelableArrayListExtra(Intent.EXTRA_STREAM))?.let { uris.addAll(it) }
            Intent.ACTION_VIEW -> i.data?.let { uris.add(it) }
        }
        val dir = File(cacheDir, "shared_in").apply { mkdirs() }
        for (u in uris) {
            try {
                var name = "plik_${System.currentTimeMillis()}"
                contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) name = c.getString(0) ?: name }
                val safe = name.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
                val out = File(dir, safe)
                contentResolver.openInputStream(u)?.use { inp -> out.outputStream().use { inp.copyTo(it) } }
                pendingShared.add(out.absolutePath)
            } catch (_: Exception) { }
        }
        i.action = null
    }

    private fun saveToMediaStore(path: String, mime: String, name: String, ringtone: Boolean = false): String? {
        val f = File(path)
        val isAudio = mime.startsWith("audio")
        val isImage = mime.startsWith("image")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = when {
                isAudio -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                isImage -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val base = when { ringtone -> Environment.DIRECTORY_RINGTONES; isAudio -> Environment.DIRECTORY_MUSIC; isImage -> Environment.DIRECTORY_PICTURES; else -> Environment.DIRECTORY_MOVIES }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, if (mime.endsWith("*")) (if (isAudio) "audio/mpeg" else "video/mp4") else mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$base/WoJan Media Studio")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                if (ringtone) put(MediaStore.Audio.Media.IS_RINGTONE, true)
            }
            val uri = contentResolver.insert(collection, values) ?: return null
            contentResolver.openOutputStream(uri)?.use { out -> FileInputStream(f).use { it.copyTo(out) } }
            values.clear(); values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(if (isAudio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES), "WoJan Media Studio").apply { mkdirs() }
        val dst = File(dir, name)
        f.copyTo(dst, overwrite = true)
        return Uri.fromFile(dst).toString()
    }
}
