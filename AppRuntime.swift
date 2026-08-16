import Foundation
import Combine

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

final class AppRuntime: ObservableObject {
    @Published var isPrayerLocked = false
    @Published var activeAlarmName: String?
    @Published var recitationVolume: Double = 1.0

    func togglePrayerLock() {
        isPrayerLocked.toggle()
        activeAlarmName = nil
    }

    func setRecitationVolume(_ value: Double) {
        recitationVolume = value.clamped(to: 0...2)
    }
}
