import UIKit
import Foundation

/// Service for presenting UIActivityViewController reliably using UIKit presentation
/// Avoids SwiftUI sheet presentation timing issues that cause black screens
@MainActor
class SharePresenter {
    
    /// Presents a share sheet using the top-most view controller
    /// Ensures all dismissals complete before presenting
    /// - Parameters:
    ///   - items: Activity items to share (must be non-empty)
    ///   - excludedActivityTypes: Optional array of activity types to exclude
    static func presentShareSheet(
        items: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil
    ) {
        Task { @MainActor in
            await PresentationCoordinator.shared.runAfterAllDismissals {
                presentShareSheetImmediate(items: items, excludedActivityTypes: excludedActivityTypes)
            }
        }
    }
    
    /// Internal method that performs the actual presentation
    private static func presentShareSheetImmediate(
        items: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil
    ) {
        // Guard: items must not be empty
        guard !items.isEmpty else {
            #if DEBUG
            print("📤 [SharePresenter] ERROR: Cannot present share sheet with empty items")
            #endif
            return
        }
        
        // Find top-most view controller
        guard let topViewController = findTopViewController() else {
            #if DEBUG
            print("📤 [SharePresenter] ERROR: Cannot find top-most view controller")
            #endif
            return
        }
        
        // Log for debugging
        #if DEBUG
        if let url = items.first as? URL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            let fileSize = fileExists ? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0 : 0
            print("📤 [SharePresenter] Presenting share sheet:")
            print("   - URL: \(url.path)")
            print("   - File exists: \(fileExists)")
            print("   - File size: \(fileSize) bytes")
            print("   - Top VC: \(type(of: topViewController))")
        }
        #endif
        
        // Create activity view controller
        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        // Set excluded activity types if provided
        if let excluded = excludedActivityTypes {
            activityVC.excludedActivityTypes = excluded
        }
        
        // Configure for iPad (popover)
        if let popover = activityVC.popoverPresentationController {
            // Use safe defaults for iPad
            if let sourceView = topViewController.view {
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(
                    x: sourceView.bounds.midX,
                    y: sourceView.bounds.midY,
                    width: 0,
                    height: 0
                )
            }
            popover.permittedArrowDirections = []
        }
        
        // Present on the appropriate view controller
        // If there's already a presented view controller, present on that instead
        let presentingVC: UIViewController
        if let presented = topViewController.presentedViewController {
            presentingVC = presented
            #if DEBUG
            print("📤 [SharePresenter] Presenting on already-presented VC: \(type(of: presented))")
            #endif
        } else {
            presentingVC = topViewController
        }
        
        // Present immediately (PresentationCoordinator already handled timing)
        presentingVC.present(activityVC, animated: true)
        #if DEBUG
        print("📤 [SharePresenter] ✅ Share sheet presented successfully")
        #endif
    }
    
    /// Finds the top-most view controller in the active window scene
    private static func findTopViewController() -> UIViewController? {
        // Get active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            #if DEBUG
            print("📤 [SharePresenter] WARNING: No active window scene found, trying alternative method")
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
    private static func findTopViewController(in viewController: UIViewController?) -> UIViewController? {
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
