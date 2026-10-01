package com.lycard.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.graphics.BitmapFactory
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "lycard/icon"

    /** 应用内更新：查安装权限 / 拉起系统安装器 */
    private val updateChannelName = "lycard/update"

    /** 图标别名（activity-alias 名字 → 资源名） */
    private val aliases = mapOf(
        "blue" to ".IconBlue",
        "red" to ".IconRed",
        "green" to ".IconGreen",
        "purple" to ".IconPurple",
        "orange" to ".IconOrange",
        "dark" to ".IconDark"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentAlias())
                    "set" -> {
                        val name = call.argument<String>("name") ?: "blue"
                        result.success(setAlias(name))
                    }
                    "pinShortcut" -> {
                        val path = call.argument<String>("path")
                        val label = call.argument<String>("label") ?: "lycard"
                        if (path == null) {
                            result.success(false)
                        } else {
                            result.success(pinShortcut(path, label))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "install" -> result.success(installApk(call.argument<String>("path")))
                    "apkPath" -> result.success(apkPath())
                    else -> result.notImplemented()
                }
            }
    }

    /** 本机已安装的 APK 在哪 —— 差分更新拿它当输入 */
    private fun apkPath(): String? = try {
        packageManager.getApplicationInfo(packageName, 0).sourceDir
    } catch (e: Exception) {
        null
    }

    /** 有没有「安装未知应用」的权限（Android 8 起每个应用单独开关，之前恒为 true） */
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** 跳到「安装未知应用」的系统设置页 */
    private fun openInstallSettings(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
        }
        true
    } catch (e: Exception) {
        false
    }

    /**
     * 拉起系统安装器装下好的 APK。
     *
     * 更新包在 App 的外部私有目录（/sdcard/Android/data/<包名>/files/update/），
     * 系统安装器**读不到这个路径**，必须走 FileProvider 换个 content:// 再授权给它。
     */
    private fun installApk(path: String?): Boolean {
        if (path == null) return false
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun currentAlias(): String {
        val pm = packageManager
        for ((name, alias) in aliases) {
            val state = pm.getComponentEnabledSetting(
                ComponentName(this, "$packageName$alias")
            )
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return name
        }
        return "blue"
    }

    private fun setAlias(name: String): Boolean {
        val target = aliases[name] ?: return false
        val pm = packageManager
        for ((_, alias) in aliases) {
            val cn = ComponentName(this, "$packageName$alias")
            val want = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            val dont = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            pm.setComponentEnabledSetting(
                cn,
                if (alias == target) want else dont,
                PackageManager.DONT_KILL_APP
            )
        }
        return true
    }

    /** 用用户选的图片 Pin 一个桌面快捷方式（图标就是那张图） */
    private fun pinShortcut(path: String, label: String): Boolean {
        return try {
            val bmp = BitmapFactory.decodeFile(path) ?: return false
            val intent = Intent(Intent.ACTION_MAIN).apply {
                setClassName(packageName, "$packageName.MainActivity")
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val info = ShortcutInfoCompat.Builder(this, "lycard-custom-${System.currentTimeMillis()}")
                .setShortLabel(label.take(10))
                .setLongLabel(label)
                .setIcon(IconCompat.createWithBitmap(bmp))
                .setIntent(intent)
                .build()
            ShortcutManagerCompat.requestPinShortcut(this, info, null)
            true
        } catch (e: Exception) {
            false
        }
    }
}
