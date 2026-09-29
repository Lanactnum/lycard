package com.lycard.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "lycard/icon"

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
