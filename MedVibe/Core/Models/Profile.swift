import Foundation
import SwiftData

// MARK: - Profile (User / Child / Parent)

@Model
class Profile {
    var name: String
    var isChild: Bool
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade)
    var records: [MedicalRecord] = []
    
    @Relationship(deleteRule: .cascade)
    var reminders: [Reminder] = []
    
    init(name: String, isChild: Bool = false) {
        self.name = name
        self.isChild = isChild
        self.createdAt = .now
    }
}
