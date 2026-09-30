package io.github.gameon223.memora.capture

/** Reads the system list of enabled accessibility services. */
object AccessibilitySettings {
    /**
     * [setting] is `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`, a colon
     * separated list of flattened component names. Package names are compared
     * case sensitively, class names allow the short `.Class` form the system
     * sometimes stores.
     */
    fun isEnabled(setting: String?, packageName: String, className: String): Boolean {
        if (setting.isNullOrBlank()) return false
        val shortName = className.removePrefix(packageName)
        for (entry in setting.split(':')) {
            val trimmed = entry.trim()
            if (trimmed.isEmpty()) continue
            val parts = trimmed.split('/')
            if (parts.size != 2) continue
            if (parts[0] != packageName) continue
            if (parts[1] == className || parts[1] == shortName) return true
        }
        return false
    }
}
