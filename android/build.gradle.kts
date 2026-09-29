allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

/**
 * 把某个 Android 子项目的 compileSdk 强制拔到 36。
 *
 * 为什么需要：插件（file_picker 等）自带 build.gradle 里写的是 compileSdk 34，
 * 但它的依赖 flutter_plugin_android_lifecycle 新版本要求 >= 36，
 * 校验 AAR metadata 时会直接失败。插件在 pub 缓存里，不能直接改，
 * 所以在这里用反射统一覆盖。
 */
fun Project.forceCompileSdk36() {
    val ext = extensions.findByName("android") ?: return
    for (name in listOf("setCompileSdkVersion", "compileSdkVersion")) {
        try {
            ext.javaClass
                .getMethod(name, Int::class.javaPrimitiveType)
                .invoke(ext, 36)
            return
        } catch (_: Exception) {
            // 换下一个方法名试
        }
    }
}

// 注意：必须在 evaluationDependsOn(":app") 之前注册，
// 否则 :app 已经评估完，afterEvaluate 会直接报错。
subprojects {
    if (state.executed) {
        forceCompileSdk36()
    } else {
        afterEvaluate { forceCompileSdk36() }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
