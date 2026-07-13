import Foundation

public protocol RTLHierarchyElaborating: Sendable {
    func elaborate(_ design: RTLDesign) -> RTLHierarchyElaborationResult
}
