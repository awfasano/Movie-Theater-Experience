import SwiftUI
import UIKit

struct CustomTextInputView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    @Binding var dynamicHeight: CGFloat
    let containerWidth: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.text = text.isEmpty ? placeholder : text
        textView.textColor = text.isEmpty ? .placeholderText : .label
        
        // Configure text container for wrapping
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // Set width constraint
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.widthAnchor.constraint(equalToConstant: containerWidth)
        ])
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if text != uiView.text {
            uiView.text = text.isEmpty ? placeholder : text
            uiView.textColor = text.isEmpty ? .placeholderText : .label
        }
        
        // Force layout update
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        
        let size = uiView.sizeThatFits(CGSize(width: containerWidth, height: .greatestFiniteMagnitude))
        if abs(size.height - dynamicHeight) > 1 {
            DispatchQueue.main.async {
                dynamicHeight = min(max(40, size.height), 120)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, onCommit: onCommit)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextInputView
        var onCommit: () -> Void
        
        init(_ textView: CustomTextInputView, onCommit: @escaping () -> Void) {
            self.parent = textView
            self.onCommit = onCommit
        }
        
        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.text = textView.text
            }
            
            // Force layout update
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                if textView.text.last == "\n" {
                    textView.text = String(textView.text.dropLast())
                    return false
                }
                textView.resignFirstResponder()
                onCommit()
                return false
            }
            return true
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = .label
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
            }
        }
    }
}

struct VisionOSTextField: View {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    @State private var dynamicHeight: CGFloat = 40
    
    var body: some View {
        GeometryReader { geometry in
            CustomTextInputView(
                text: $text,
                placeholder: placeholder,
                onCommit: onCommit,
                dynamicHeight: $dynamicHeight,
                containerWidth: geometry.size.width - 32 // Account for padding
            )
            .frame(width: geometry.size.width - 32, height: dynamicHeight)
            .background(Color(uiColor: .systemBackground).opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal, 16)
        }
        .frame(height: dynamicHeight)
    }
}
