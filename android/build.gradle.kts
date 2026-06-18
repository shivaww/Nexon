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
