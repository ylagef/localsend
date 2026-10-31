package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import com.pravera.flutter_foreground_task.service.ForegroundService as AndroidForegroundService
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone


private const val CHANNEL = "org.localsend.localsend_app/localsend"
private const val REQUEST_CODE_PICK_DIRECTORY = 1
private const val REQUEST_CODE_PICK_DIRECTORY_PATH = 2
private const val REQUEST_CODE_PICK_FILE = 3
private const val REQUEST_CODE_LOCAL_NETWORK = 4

// Not available as a constant in compileSdk 36.
private const val PERMISSION_ACCESS_LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
private const val API_LEVEL_ANDROID_17 = 37

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    /// share_handler drops share intents arriving via onNewIntent while the Dart side
    /// is not subscribed to its media stream yet, which happens when this singleTask
    /// activity is relaunched into an existing task while the app is still starting.
    /// Hold such intents back until Dart reports readiness ("shareIntentReady"), then
    /// replay them through the regular plugin path.
    // Readiness belongs to the retained engine, not to an individual Activity.

    private fun openReceiveIntent(intent: Intent) {
        if (!receiveReady || intent.action != "org.localsend.OPEN_RECEIVE") return
        val sessionId = intent.getStringExtra("sessionId") ?: return
        val kind = intent.getStringExtra("kind") ?: return
        ReceiveNotifications.channel?.invokeMethod("onNotificationClicked", mapOf("sessionId" to sessionId, "kind" to kind))
        intent.action = null
    }

    override fun onResume() {
        super.onResume()
        ReceiveNotifications.visible = true
        openReceiveIntent(intent)
    }

    override fun onPause() {
        ReceiveNotifications.visible = false
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Dart closes the native Rust listeners before releasing a taskless engine.
        if (attachedActivity?.get() === this) attachedActivity = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        pendingResult?.error("CANCELED", "LocalSend screen was closed", null)
        pendingResult = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        openReceiveIntent(intent)
        if (!shareIntentReady && (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE)) {
            pendingShareIntents.add(intent)
            return
        }
        super.onNewIntent(intent)
    }

    private fun onShareIntentReady() {
        shareIntentReady = true
        val pending = pendingShareIntents.toList()
        pendingShareIntents.clear()
        for (intent in pending) {
            super.onNewIntent(intent)
        }
    }

    // Overriding the static methods we need from the Java class, as described
    // in the documentation of `FlutterActivity.NewEngineIntentBuilder`
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(MAIN_ENGINE)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    companion object {
        private const val MAIN_ENGINE = "localsend_main"
        private val pendingShareIntents = mutableListOf<Intent>()
        private var shareIntentReady = false
        private var receiveReady = false
        private var attachedActivity: WeakReference<MainActivity>? = null

        private fun clearRetainedEngine(engine: FlutterEngine) {
            if (FlutterEngineCache.getInstance().get(MAIN_ENGINE) === engine) {
                FlutterEngineCache.getInstance().remove(MAIN_ENGINE)
                ReceiveNotifications.channel = null
                receiveReady = false
                shareIntentReady = false
                pendingShareIntents.clear()
            }
        }
        fun withNewEngine(): NewEngineIntentBuilder {
            return NewEngineIntentBuilder(MainActivity::class.java)
        }

        fun createDefaultIntent(launchContext: Context): Intent {
            return withNewEngine().build(launchContext)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachedActivity = WeakReference(this)
        FlutterEngineCache.getInstance().put(MAIN_ENGINE, flutterEngine)
        val appContext = applicationContext
        val activity = WeakReference(this)
        val files = AndroidFileAccess(appContext)
        val receiveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.localsend.localsend_app/receive")
        ReceiveNotifications.channel = receiveChannel
        receiveChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableReceiveAlerts" -> result.success(ReceiveNotifications.enable(appContext, call.argument<String>("channelName") ?: "LocalSend"))
                "showReceiveNotification" -> result.success(ReceiveNotifications.show(appContext, call.arguments as? Map<*, *> ?: emptyMap<String, Any>()))
                "removeReceiveNotification" -> { ReceiveNotifications.remove(appContext, call.arguments as? String ?: ""); result.success(null) }
                "hideReceiveAlerts" -> { ReceiveNotifications.hide(appContext); result.success(null) }
                "releaseDetachedEngine" -> {
                    Handler(Looper.getMainLooper()).post {
                        val release = attachedActivity?.get()?.isDestroyed != false &&
                            !AndroidForegroundService.isRunningServiceState.value &&
                            FlutterEngineCache.getInstance().get(MAIN_ENGINE) === flutterEngine
                        result.success(release)
                        if (release) {
                            clearRetainedEngine(flutterEngine)
                            Handler(Looper.getMainLooper()).post { flutterEngine.destroy() }
                        }
                    }
                }
                "receiveNotificationsReady" -> { ReceiveNotifications.clearOrphanedRequests(appContext); receiveReady = true; activity.get()?.let { it.openReceiveIntent(it.intent) }; result.success(null) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (host == null) result.error("NO_ACTIVITY", "Open LocalSend to choose a folder", null)
                    else { host.pendingResult = result; host.openDirectoryPicker(onlyPath = false) }
                }

                "pickFiles" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (host == null) result.error("NO_ACTIVITY", "Open LocalSend to choose files", null)
                    else { host.pendingResult = result; host.openFilePicker() }
                }

                "pickDirectoryPath" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (host == null) result.error("NO_ACTIVITY", "Open LocalSend to choose a folder", null)
                    else { host.pendingResult = result; host.openDirectoryPicker(onlyPath = true) }
                }

                "createDirectory" -> files.handleCreateDirectory(call, result)

                "getFileDescriptor" -> files.handleGetFileDescriptor(call, result)

                "createFile" -> files.handleCreateFile(call, result)

                "openFileForWriting" -> files.handleOpenFileForWriting(call, result)

                "scanFile" -> files.handleScanFile(call, result)

                "openContentUri" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (host == null) result.error("NO_ACTIVITY", "Open LocalSend to view a file", null)
                    else { openUri(host, call.argument<String>("uri")!!); result.success(null) }
                }

                "openGallery" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (host == null) result.error("NO_ACTIVITY", "Open LocalSend to view the gallery", null)
                    else { host.openGallery(); result.success(null) }
                }

                "shareIntentReady" -> {
                    activity.get()?.onShareIntentReady()
                    result.success(null)
                }

                "isAnimationsEnabled" -> {
                    result.success(files.isAnimationsEnabled())
                }

                "getDownloadsDirectory" -> {
                    result.success(files.getDownloadsDirectory())
                }

                "requestLocalNetworkPermission" -> {
                    val host = activity.get()?.takeUnless { it.isDestroyed }
                    if (Build.VERSION.SDK_INT < API_LEVEL_ANDROID_17 ||
                        appContext.checkSelfPermission(PERMISSION_ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else if (host == null) {
                        result.success(false)
                    } else {
                        host.pendingPermissionResult = result
                        host.requestPermissions(arrayOf(PERMISSION_ACCESS_LOCAL_NETWORK), REQUEST_CODE_LOCAL_NETWORK)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_LOCAL_NETWORK) {
            pendingPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermissionResult = null
        }
    }

    private fun openDirectoryPicker(onlyPath: Boolean) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        startActivityForResult(
            intent,
            if (onlyPath) REQUEST_CODE_PICK_DIRECTORY_PATH else REQUEST_CODE_PICK_DIRECTORY
        )
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra("multi-pick", true)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FILE)
    }

    @SuppressLint("WrongConstant")
    @Override
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingResult?.error("CANCELED", "Canceled", null)
            pendingResult = null
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("Error $resultCode", "Failed to access directory or file", null)
            pendingResult = null
            return
        }

        when (requestCode) {
            REQUEST_CODE_PICK_DIRECTORY -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    val files = mutableListOf<FileInfo>()
                    listFiles(uri, files)
                    val resultData = PickDirectoryResult(uri.toString(), files)
                    pendingResult?.success(resultData.toMap())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_DIRECTORY_PATH -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    pendingResult?.success(uri.toString())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_FILE -> {
                val uriList: List<Uri> = when {
                    data.clipData != null -> {
                        val clipData = data.clipData
                        val uris = mutableListOf<Uri>()
                        for (i in 0 until clipData!!.itemCount) {
                            uris.add(clipData.getItemAt(i).uri)
                        }
                        uris
                    }

                    data.data != null -> listOf(data.data!!)
                    else -> {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                }

                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                val resultList = mutableListOf<FileInfo>()
                for (uri in uriList) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    val documentFile = FastDocumentFile.fromDocumentUri(this, uri)
                    if (documentFile == null) {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                    resultList.add(
                        FileInfo(
                            name = documentFile.name,
                            size = documentFile.size,
                            uri = uri.toString(),
                            lastModified = documentFile.lastModified?.toRfc3339(),
                        )
                    )
                }

                pendingResult?.success(resultList.map { it.toMap() })
                pendingResult = null
            }
        }
    }

    private fun listFiles(uri: Uri, files: MutableList<FileInfo>) {
        val pickedDir: FastDocumentFile = FastDocumentFile.fromTreeUri(this, uri)

        for (file in pickedDir.listFiles()) {
            if (file.isDirectory) {
                // Recursive call
                listFiles(file.uri, files)
            } else if (file.isFile) {
                files.add(
                    FileInfo(
                        name = file.name,
                        size = file.size,
                        uri = file.uri.toString(),
                        lastModified = file.lastModified?.toRfc3339(),
                    ),
                )
            }
        }
    }

    private fun openGallery() {
        val intent = Intent()
        intent.action = Intent.ACTION_VIEW
        intent.type = "image/*"
        startActivity(intent)
    }
}

data class PickDirectoryResult(
    val directoryUri: String,
    val files: List<FileInfo>,
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "directoryUri" to directoryUri,
            "files" to files.map { it.toMap() }
        )
    }
}

data class FileInfo(
    val name: String,
    val size: Long,
    val uri: String,
    val lastModified: String?
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "name" to name,
            "size" to size,
            "uri" to uri,
            "lastModified" to lastModified
        )
    }
}

/// Formats milliseconds since epoch as an RFC 3339 string in UTC.
private fun Long.toRfc3339(): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date(this))
}
