import UIKit
import Foundation

/// Centralized coordinator for safe SwiftUI sheet presentation
/// Ensures sheets are presented only after all dismissals complete
@MainActor
class PresentationCoordinator {
    static let shared = PresentationCoordinator()
    
    private var isPresenting = false
    private let presentationQueue = DispatchQueue(label: "com.medvibe.presentation", qos: .userInitiated)
    
    private init() {}
    
    /// Waits until all view controller dismissals are complete
    /// Uses retry loop to ensure stable presentation state
    /// - Parameter maxAttempts: Maximum number of retry attempts (default: 10)
    /// - Parameter delayMs: Delay between attempts in milliseconds (default: 50)
    func runAfterAllDismissals(
        maxAttempts: Int = 10,
        delayMs: UInt64 = 50,
        _ block: @MainActor @escaping () -> Void
    ) async {
        // Wait for any ongoing presentations to complete
        while isPresenting {
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }
        
        isPresenting = true
        defer { isPresenting = false }
        
        // Find top-most view controller
        guard let topVC = findTopViewController() else {
            #if DEBUG
            print("📱 [PresentationCoordinator] WARNING: No top VC found, executing block anyway")
            #endif
            block()
            return
        }
        
        // Wait for dismissals to complete
        var attempts = 0
        while attempts < maxAttempts {
            // Check if there's a presented view controller or dismissal in progress
            let hasPresented = topVC.presentedViewController != nil
            let isBeingDismissed = topVC.isBeingDismissed || topVC.isMovingFromParent
            
            if !hasPresented && !isBeingDismissed {
                // Safe to present
                #if DEBUG
                print("📱 [PresentationCoordinator] ✅ Safe to present after \(attempts) attempts")
                #endif
                break
            }
            
            #if DEBUG
            if attempts == 0 {
                print("📱 [PresentationCoordinator] Waiting for dismissals to complete...")
            }
            #endif
            
            // Wait before next check
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            attempts += 1
        }
        
        // Additional small delay to ensure animation completion
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Execute the block
        block()
    }
    
    /// Safely presents a SwiftUI sheet by setting a state flag
    /// Ensures all dismissals complete before setting the flag
    /// - Parameter setFlag: Closure that sets the SwiftUI sheet presentation flag
    func presentSwiftUISheetSafely(setFlag: @MainActor @escaping () -> Void) async {
        await runAfterAllDismissals {
            setFlag()
            #if DEBUG
            print("📱 [PresentationCoordinator] ✅ Sheet presentation flag set")
            #endif
        }
    }
    
    /// Finds the top-most view controller in the active window scene
    private func findTopViewController() -> UIViewController? {
        // Get active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            #if DEBUG
            print("📱 [PresentationCoordinator] WARNING: No active window scene, trying fallback")
            #endif
            // Fallback: try to get any window
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ??
                              UIApplication.shared.windows.first else {
                return nil
            }
            return findTopViewController(in: window.rootViewController)
        }
        
        return findTopViewController(in: window.rootViewController)
    }
    
    /// Recursively finds the top-most view controller
    private func findTopViewController(in viewController: UIViewController?) -> UIViewController? {
        guard let vc = viewController else { return nil }
        
        // If there's a presented view controller, use that
        if let presented = vc.presentedViewController {
            return findTopViewController(in: presented)
        }
        
        // Handle navigation controller
        if let nav = vc as? UINavigationController {
            return findTopViewController(in: nav.visibleViewController)
        }
        
        // Handle tab bar controller
        if let tab = vc as? UITabBarController {
            return findTopViewController(in: tab.selectedViewController)
        }
        
        // Handle split view controller
        if let split = vc as? UISplitViewController {
            return findTopViewController(in: split.viewControllers.last)
        }
        
        // This is the top-most view controller
        return vc
    }
}
