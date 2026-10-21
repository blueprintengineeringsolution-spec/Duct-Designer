allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Auto-set a namespace for old plugins that don't declare one.
// This block must stay ABOVE evaluationDependsOn.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            if (androidExt.namespace == null) {
                val manifest = file("src/main/AndroidManifest.xml")
                val pkg = if (manifest.exists()) {
                    Regex("package=\"([^\"]+)\"")
                        .find(manifest.readText())?.groupValues?.get(1)
                } else null
                androidExt.namespace = pkg ?: group.toString()
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