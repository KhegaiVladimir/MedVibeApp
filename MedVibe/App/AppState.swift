import Foundation
import SwiftUI
import Combine

/// App-level state for handling store resets and model invalidation
class AppState: ObservableObject {
    static let shared = AppState()
    
    /// Generation token that increments when store is reset
    /// Views can observe this to rebuild rows when store resets
    @Published var storeGeneration: Int = 0
    
    private init() {}
    
    /// Call this when store is reset to force views to rebuild
    func incrementStoreGeneration() {
        storeGeneration += 1
        #if DEBUG
        print("🔄 Store generation incremented to \(storeGeneration)")
        #endif
    }
}
