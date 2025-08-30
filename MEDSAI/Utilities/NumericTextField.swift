import SwiftUI
import UIKit

struct NumericTextField: UIViewRepresentable {
    @Binding var value: Double?
    var placeholder: String = "Amount"
    var allowsDecimal: Bool = true
    var maxFractionDigits: Int = 2

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = allowsDecimal ? .decimalPad : .numberPad
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.updateTextField(tf, from: value)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.maxFractionDigits = maxFractionDigits
        context.coordinator.allowsDecimal = allowsDecimal
        context.coordinator.updateTextField(uiView, from: value)
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var value: Double?
        var allowsDecimal = true
        var maxFractionDigits = 2

        private let formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.usesGroupingSeparator = false
            f.maximumFractionDigits = 6
            return f
        }()

        init(value: Binding<Double?>) { _value = value }

        @objc func editingChanged(_ textField: UITextField) {
            guard let text = textField.text, !text.isEmpty else {
                value = nil; return
            }
            if let num = formatter.number(from: text)?.doubleValue {
                value = num
            }
        }

        func updateTextField(_ tf: UITextField, from value: Double?) {
            let current = tf.text ?? ""
            let desired: String = {
                guard let v = value else { return "" }
                return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
            }()
            if current != desired && !tf.isFirstResponder {
                tf.text = desired
            }
        }

        // Block non-numeric characters and limit decimals
        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {

            if string.isEmpty { return true } // backspace

            let dec = formatter.decimalSeparator ?? "."
            let allowedDigits = CharacterSet.decimalDigits
            let allowed = allowsDecimal ? allowedDigits.union(.init(charactersIn: dec)) : allowedDigits

            if string.rangeOfCharacter(from: allowed.inverted) != nil { return false }

            let current = textField.text ?? ""
            guard let r = Range(range, in: current) else { return false }
            let next = current.replacingCharacters(in: r, with: string)

            if allowsDecimal {
                let parts = next.components(separatedBy: dec)
                if parts.count > 2 { return false }
                if parts.count == 2, parts[1].count > maxFractionDigits { return false }
            } else if next.contains(dec) {
                return false
            }

            if let num = formatter.number(from: next)?.doubleValue { value = num }
            else if next.isEmpty { value = nil }

            return true
        }
    }
}
