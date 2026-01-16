import Foundation
import SwiftData

@Model
class MedicalRecord {
    var title: String
    var summary: String
    var date: Date
    
    // optional link to reminder
    @Relationship
    var reminder: Reminder?
    
    init(
        title: String,
        summary: String,
        date: Date = .now
    ) {
        self.title = title
        self.summary = summary
        self.date = date
    }
}
