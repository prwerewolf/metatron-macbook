import Foundation

// An in-memory double prevents the migration tests from touching real settings.
public final class UserDefaults {
    public static let standard = UserDefaults()
    public private(set) var values: [String: Any]

    public init(_ values: [String: Any] = [:]) { self.values = values }
    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
    public func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@main
struct PreferenceMigrationTests {
    static func main() {
        let legacy: [String: Any] = [
            "metatron_speech_mode": "speed",
            "metatron_retention": "Keep Last 10 Items",
            "metatron_auto_copy": true,
            "metatron_auto_insert": false,
            "metatron_pill_orientation": "vertical",
            "metatron_hotkey": "F8",
            "metatron_mode": "toggle",
            "metatron_style": "verbatim",
            "metatron_auto_adaptive": false,
            "metatron_sound": false,
            "metatron_vocab": "Asteria, Lumora",
            "metatron_replacements": "brb=Be right back",
            "metatron_correction_learning": true,
            "metatron_learned_vocabulary": ["Asteria", "Lumora"],
            "metatron_microphone_uid": "synthetic-input-uid",
            "metatron_pill_x": -240.5,
            "metatron_pill_y": 48.0,
            "metatron_pill_snap": "Left Edge",
            "metatron_pill_display": "synthetic-display-id",
            "unrelated_setting": "untouched"
        ]
        let expected: [String: Any] = [
            "presstowrite_speech_mode": "speed",
            "presstowrite_retention": "Keep Last 10 Items",
            "presstowrite_auto_copy": true,
            "presstowrite_auto_insert": false,
            "presstowrite_pill_orientation": "vertical",
            "presstowrite_hotkey": "F8",
            "presstowrite_mode": "toggle",
            "presstowrite_style": "verbatim",
            "presstowrite_auto_adaptive": false,
            "presstowrite_sound": false,
            "presstowrite_vocab": "Asteria, Lumora",
            "presstowrite_replacements": "brb=Be right back",
            "presstowrite_correction_learning": true,
            "presstowrite_learned_vocabulary": ["Asteria", "Lumora"],
            "presstowrite_microphone_uid": "synthetic-input-uid",
            "presstowrite_pill_x": -240.5,
            "presstowrite_pill_y": 48.0,
            "presstowrite_pill_snap": "Left Edge",
            "presstowrite_pill_display": "synthetic-display-id",
            "unrelated_setting": "untouched"
        ]
        let migrated = UserDefaults(legacy)
        PreferenceMigration.migrate(migrated)
        precondition(NSDictionary(dictionary: migrated.values).isEqual(to: expected),
                     "Every supported preference must be preserved and its legacy key removed")
        PreferenceMigration.migrate(migrated)
        precondition(NSDictionary(dictionary: migrated.values).isEqual(to: expected),
                     "Repeating migration must not alter saved settings")

        let currentWins = UserDefaults([
            "metatron_auto_copy": true, "presstowrite_auto_copy": false,
            "metatron_vocab": "Asteria", "presstowrite_vocab": "",
            "metatron_learned_vocabulary": ["Lumora"], "presstowrite_learned_vocabulary": [String](),
            "metatron_microphone_uid": "old-input", "presstowrite_microphone_uid": "current-input",
            "metatron_pill_x": 500.0, "presstowrite_pill_x": 0.0
        ])
        let currentExpected: [String: Any] = [
            "presstowrite_auto_copy": false,
            "presstowrite_vocab": "",
            "presstowrite_learned_vocabulary": [String](),
            "presstowrite_microphone_uid": "current-input",
            "presstowrite_pill_x": 0.0
        ]
        PreferenceMigration.migrate(currentWins)
        precondition(NSDictionary(dictionary: currentWins.values).isEqual(to: currentExpected),
                     "Existing current values, including empty and false, must win")
        currentWins.set("stale-input", forKey: "metatron_microphone_uid")
        PreferenceMigration.migrate(currentWins)
        precondition(NSDictionary(dictionary: currentWins.values).isEqual(to: currentExpected),
                     "A later migration must still retire stale keys without replacing current values")

        let retired = UserDefaults([
            "metatron_engine": "retired-cloud",
            "metatron_groq_key": "test-only",
            "metatron_openai_key": "test-only",
            "presstowrite_engine": "retired-cloud",
            "presstowrite_groq_key": "test-only",
            "presstowrite_openai_key": "test-only"
        ])
        PreferenceMigration.migrate(retired)
        precondition(retired.values.isEmpty, "Retired cloud settings and credentials must be removed, never copied")

        let fresh = UserDefaults()
        PreferenceMigration.migrate(fresh)
        precondition(fresh.values.isEmpty, "A fresh install must keep its existing application defaults")
        precondition(UserDefaults.standard.values.isEmpty, "Tests must use only their injected settings store")
        print("Preference migration tests passed")
    }
}
