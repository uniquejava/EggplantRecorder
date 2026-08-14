import SwiftUI

struct OptionsFeatureRow<MenuContent: View>: View {
    let icon: String
    let title: String
    var showsMenu: Bool = false
    var showsGear: Bool = false
    @Binding var isOn: Bool
    var enabled: Bool
    var forceChecked: Bool = false
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.35))
                .frame(width: 18)

            if showsMenu, enabled {
                Menu {
                    menuContent()
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .menuStyle(.borderlessButton)
            } else {
                Text(title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsMenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }

            if showsGear {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.28))
            }

            Spacer(minLength: 6)

            OMICheckbox(
                isOn: $isOn,
                enabled: enabled && !forceChecked,
                forceOn: forceChecked
            )
        }
        .frame(minHeight: 22)
        .opacity(enabled || forceChecked ? 1 : 0.72)
    }
}

extension OptionsFeatureRow where MenuContent == EmptyView {
    init(
        icon: String,
        title: String,
        showsMenu: Bool = false,
        showsGear: Bool = false,
        isOn: Binding<Bool>,
        enabled: Bool,
        forceChecked: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.showsMenu = showsMenu
        self.showsGear = showsGear
        self._isOn = isOn
        self.enabled = enabled
        self.forceChecked = forceChecked
        self.menuContent = { EmptyView() }
    }
}

struct OptionsParamRow<Content: View>: View {
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 18)
            content()
                .font(.system(size: 13))
        }
        .frame(minHeight: 24)
    }
}

struct OptionsSizeField: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: 44)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

struct OptionsPillLabel: View {
    let text: String
    var enabled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(enabled ? Color.black.opacity(0.85) : Color.black.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.95 : 0.55))
            )
    }
}

/// Unchecked fill must not be `Color.clear` — SwiftUI skips hit-testing on clear fills.
struct OMICheckbox: View {
    @Binding var isOn: Bool
    var enabled: Bool = true
    var forceOn: Bool = false

    private var checked: Bool { forceOn || isOn }

    var body: some View {
        Button {
            guard enabled else { return }
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(checked ? Color(red: 0.04, green: 0.52, blue: 1) : Color.white.opacity(0.001))
                .frame(width: 15, height: 15)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(checked ? Color.clear : Color.white.opacity(enabled ? 0.45 : 0.22), lineWidth: 1.2)
                )
                .overlay {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
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
