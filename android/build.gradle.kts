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

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ---------------------------------------------------------------------------
// Safety net: force every Android *plugin* subproject to compile against at
// least SDK 36.
//
// Some Flutter plugins still hard-code an older compileSdk (file_picker pinned
// 34 for a long time). When one of their own dependencies requires 36+, the
// build dies with "Dependency ':x' requires ... compile against version 36".
//
// This MUST be registered before the evaluationDependsOn(":app") block below:
// that block forces :app to evaluate immediately, and you cannot add an
// afterEvaluate hook to an already-evaluated project. The :app project is
// skipped anyway (it sets its own compileSdk), and state.executed is checked
// so this can never throw if evaluation order shifts again.
//
// Written reflectively and wrapped in runCatching so it degrades to a no-op on
// any AGP version whose extension shape differs, rather than failing the build.
// ---------------------------------------------------------------------------
subprojects {
    if (name != "app" && !state.executed) {
        afterEvaluate {
            val androidExt = extensions.findByName("android") ?: return@afterEvaluate
            runCatching {
                val setter = androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterTypes.size == 1
                }
                val getter = androidExt.javaClass.methods.firstOrNull {
                    it.name == "getCompileSdk" && it.parameterTypes.isEmpty()
                }
                val current = getter?.invoke(androidExt) as? Int
                if (setter != null && (current == null || current < 36)) {
                    setter.invoke(androidExt, 36)
                    logger.lifecycle("Raised compileSdk to 36 for :${project.name}")
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
