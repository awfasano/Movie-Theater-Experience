//
//  CustomTextInput.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/11/24.
//

import SwiftUI
import UIKit

struct CustomTextInputView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    @Binding var dynamicHeight: CGFloat // Provided by parent

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = false // Handles scroll inside the UIScrollView
        textView.backgroundColor = UIColor.clear // To match SwiftUI's default background
        textView.text = placeholder
        textView.textColor = UIColor.placeholderText
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text == placeholder && !text.isEmpty {
            uiView.text = text
            uiView.textColor = UIColor.label // Use default text color
        } else if text.isEmpty {
            uiView.text = placeholder
            uiView.textColor = UIColor.placeholderText
        } else {
            uiView.text = text
        }
        
        // Dynamically adjust the height of the UITextView
        let size = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: CGFloat.infinity))
        if size.height != dynamicHeight {
            DispatchQueue.main.async {
                self.dynamicHeight = size.height // Update the height
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
            self.parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                if textView.text.last == "\n" {
                    textView.text = String(textView.text.dropLast())
                    return false
                } else {
                    textView.resignFirstResponder() // Dismiss keyboard
                    self.onCommit()
                    return false
                }
            }
            return true
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = UIColor.label // Default text color
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
    }
}
