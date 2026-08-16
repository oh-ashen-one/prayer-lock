import Foundation
import SwiftData

@Model
final class Alarm {
    @Attribute(.unique) var id: UUID
    var name: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "Prayer Alarm",
        hour: Int = 6,
        minute: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
    }
}

@Model
final class SealObject {
    @Attribute(.unique) var id: UUID
    var name: String
    var imageData: Data?

    init(
        id: UUID = UUID(),
        name: String = "",
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
    }
}

@Model
final class EmergencyUse {
    @Attribute(.unique) var id: UUID
    var note: String

    init(
        id: UUID = UUID(),
        note: String = ""
    ) {
        self.id = id
        self.note = note
    }
}
