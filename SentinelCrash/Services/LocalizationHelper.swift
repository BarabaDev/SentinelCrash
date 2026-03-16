import Foundation

extension String {
    /// Shortcut for NSLocalizedString
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Localized with format arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}
