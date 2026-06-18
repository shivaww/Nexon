// Top-level build file for TermuxForge Android project.
// This file is managed by Flutter and should not typically require
// manual edits. Plugin configuration is handled via settings.gradle.kts.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Root-level clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Configure subprojects
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureNamespace: (Project) -> Unit = { proj ->
        try {
            val android = proj.extensions.findByName("android") as? com.android.build.gradle.LibraryExtension
            if (android != null) {
                android.compileSdk = 35
                if (android.namespace == null) {
                val manifestFile = proj.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    val matcher = java.util.regex.Pattern.compile("""package="([^"]+)"""").matcher(content)
                    if (matcher.find()) {
                        android.namespace = matcher.group(1)
                    }
                }
            }
        } catch (ignored: Exception) {}
    }

    if (state.executed) {
        configureNamespace(this)
    } else {
        afterEvaluate { configureNamespace(this) }
    }
}
