extension ReferenceStore {
    /// The canonical keys of the bundled tables, so identify output (`food_group`, `device_type`, materials)
    /// lines up with the factor model. Falls back to the built-in list for an empty store.
    public var vocabulary: ReferenceVocabulary {
        let foodGroups = Set(foods.allRecords.map(\.group)).sorted()
        let deviceTypes = Set(devices.allRecords.map(\.defaults.deviceType)).sorted()
        let materialKeys = Set(fibers.allRecords.map(\.material) + materials.allRecords.map(\.endOfLife.material)).sorted()
        guard !foodGroups.isEmpty, !deviceTypes.isEmpty, !materialKeys.isEmpty else { return .default }
        return ReferenceVocabulary(foodGroups: foodGroups, deviceTypes: deviceTypes, materials: materialKeys)
    }
}
