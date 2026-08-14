import SwiftUI

struct OptionsFeatureRow: View {
    let icon: String
    let title: String
    var showsMenu: Bool = false
    var showsGear: Bool = false
    var menuItems: [OptionsMenuItem] = []
    var onMenuSelect: ((String) -> Void)? = nil
    @Binding var isOn: Bool
    var enabled: Bool
    var forceChecked: Bool = false

    private let labelOpacity: Double = 0.92
    private let mutedOpacity: Double = 0.4

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.32))
                .frame(width: 16)

            if showsMenu, enabled, !menuItems.isEmpty {
                OptionsCompactMenuTrigger(
                    title: title,
                    items: menuItems,
                    onSelect: { id in onMenuSelect?(id) }
                )
            } else {
                Text(title)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(enabled ? labelOpacity : mutedOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsMenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }

            if showsGear {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.25))
            }

            OptionsCheckbox(
                isOn: $isOn,
                enabled: enabled && !forceChecked,
                forceOn: forceChecked
            )
        }
        .frame(minHeight: 20)
        .opacity(enabled || forceChecked ? 1 : 0.72)
    }
}

struct OptionsParamRow<Content: View>: View {
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)
            content()
                .font(.system(size: 11.5))
        }
        .frame(minHeight: 22)
    }
}

struct OptionsSizeField: View {
    let text: String

    private let fieldFill = Color(red: 0.122, green: 0.129, blue: 0.145) // #1f2125
    private let fieldStroke = Color(red: 0.290, green: 0.306, blue: 0.341) // #4a4e57

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Color(red: 0.910, green: 0.918, blue: 0.929))
            .frame(minWidth: 36)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(fieldStroke, lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct OptionsPillLabel: View {
    let text: String
    var enabled: Bool = false

    private let fieldFill = Color(red: 0.122, green: 0.129, blue: 0.145)
    private let fieldStroke = Color(red: 0.290, green: 0.306, blue: 0.341)

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(enabled ? Color.white.opacity(0.9) : Color.white.opacity(0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(fieldStroke, lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// Unchecked fill must not be `Color.clear` — SwiftUI skips hit-testing on clear fills.
struct OptionsCheckbox: View {
    @Binding var isOn: Bool
    var enabled: Bool = true
    var forceOn: Bool = false

    private var checked: Bool { forceOn || isOn }

    private let uncheckedStroke = Color(red: 0.545, green: 0.565, blue: 0.600) // #8b9099
    private let uncheckedFill = Color(red: 0.122, green: 0.129, blue: 0.145) // #1f2125
    private let checkedFill = Color(red: 0.239, green: 0.494, blue: 1.0) // #3d7eff

    var body: some View {
        Button {
            guard enabled else { return }
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(checked ? checkedFill : uncheckedFill)
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(checked ? Color.clear : uncheckedStroke.opacity(enabled ? 1 : 0.45), lineWidth: 1)
                )
                .overlay {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || forceOn ? 1 : 0.55)
    }
}
