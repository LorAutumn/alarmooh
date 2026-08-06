import AlarmoohCore
import AppKit
import OSLog

let log = Logger(subsystem: "io.github.lorautumn.alarmooh", category: "startup")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source = EventKitCalendarSource()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            guard await source.requestAccess() else {
                log.error("Kalenderzugriff verweigert")
                return
            }
            let calendars = (try? source.calendars()) ?? []
            log.info("\(calendars.count) Kalender: \(calendars.map(\.title).joined(separator: ", "))")

            let now = Date()
            let events = (try? source.events(from: now, to: now.addingTimeInterval(86_400))) ?? []
            log.info("\(events.count) Termine in den naechsten 24 h")
        }
    }
}
