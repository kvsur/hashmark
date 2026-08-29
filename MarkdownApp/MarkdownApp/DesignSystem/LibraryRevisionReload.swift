import SwiftUI

private struct LibraryRevisionReload: ViewModifier {
    let revision: Int
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: revision) { _ in action() }
    }
}

extension View {
    /// Keeps live document consumers aligned with debounced presenter revisions on iOS 16+.
    func reloadsOnLibraryRevision(_ revision: Int, perform action: @escaping () -> Void) -> some View {
        modifier(LibraryRevisionReload(revision: revision, action: action))
    }
}
