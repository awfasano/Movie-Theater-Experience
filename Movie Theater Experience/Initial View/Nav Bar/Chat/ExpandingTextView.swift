import SwiftUI
import RealityKit
import RealityKitContent

struct ExpandingTextField: View {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    @Binding var dynamicHeight: CGFloat // Provided by parent

    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color.secondary)
                        .padding(.leading, 5)
                        .padding(.top, 8)
                }
                TextEditor(text: $text)
                    .frame(minHeight: dynamicHeight, maxHeight: dynamicHeight)
                    .onChange(of: text) {
                        // Use 'geometry.size.width' as the available width
                        let constraintSize = CGSize(width: geometry.size.width, height: .infinity)
                        let newSize = text.size(constraint: constraintSize)
                        dynamicHeight = max(minHeight, min(newSize.height, maxHeight))
                    }
                    .onSubmit {
                        onCommit()
                    }
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary, lineWidth: 1)
                    )
            }
        }
        .frame(minHeight: dynamicHeight, maxHeight: dynamicHeight)
    }
}

// Adjusted String extension remains the same…
extension String {
    func size(constraint: CGSize) -> CGSize {
        let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18)]
        let options: NSStringDrawingOptions = [.usesFontLeading, .usesLineFragmentOrigin]
        return (self as NSString).boundingRect(with: constraint, options: options, attributes: attributes, context: nil).size
    }
}
