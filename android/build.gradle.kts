// Do NOT pin plugin versions here; Flutter manages them.

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    // No classpath deps here; versions are managed by Flutter via settings.gradle
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Put all Android build output under the workspace /build
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    layout.buildDirectory.set(newSubprojectBuildDir)
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
