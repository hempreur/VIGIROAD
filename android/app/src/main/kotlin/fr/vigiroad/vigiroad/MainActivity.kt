package fr.vigiroad.vigiroad

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Mise à jour de l'application hors Play Store : informations de version,
 * autorisation « installer des applications inconnues » et installation de
 * l'APK téléchargé par l'API officielle PackageInstaller. Android affiche
 * toujours sa propre confirmation et refuse un APK signé par une autre clé.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        current = this
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "appInfo" -> result.success(appInfo())
                "canInstall" -> result.success(canInstall())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
                        )
                    }
                    result.success(true)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("install", "Chemin de l'APK manquant", null)
                    } else {
                        try {
                            install(File(path))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install", e.message ?: e.toString(), null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    private fun appInfo(): Map<String, Any?> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to info.versionName,
            "versionCode" to code,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun install(apk: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        params.setSize(apk.length())
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("vigiroad.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(this, InstallResultReceiver::class.java)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            // Android 12+ : le système complète l'intention avec le résultat.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
            val pending = PendingIntent.getBroadcast(this, id, intent, flags)
            session.commit(pending.intentSender)
        }
    }

    companion object {
        const val CHANNEL = "fr.vigiroad/updater"
        var channel: MethodChannel? = null
        var current: MainActivity? = null
    }
}

/** Résultat de l'installation : confirmation à afficher, ou échec à signaler. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    val activity = MainActivity.current
                    if (activity != null) {
                        activity.startActivity(confirm)
                    } else {
                        context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Unit // l'application est remplacée et relancée par l'utilisateur
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "code $status"
                MainActivity.channel?.invokeMethod("installFailed", mapOf("status" to status, "message" to message))
            }
        }
    }
}
