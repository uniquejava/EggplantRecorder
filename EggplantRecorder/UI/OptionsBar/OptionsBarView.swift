import SwiftUI

struct OptionsBarView: View {
    @ObservedObject var model: OptionsBarModel

    /// OMI-like column widths: 260 + 260 + 100 (+ 2 dividers).
    private let leftWidth: CGFloat = 260
    private let middleWidth: CGFloat = 260
    private let rightWidth: CGFloat = 100
    private let panelHeight: CGFloat = 230
    private let cornerRadius: CGFloat = 20

    private var panelWidth: CGFloat { leftWidth + middleWidth + rightWidth + 2 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                OptionsBarLeftColumn(model: model)
                    .padding(.horizontal, 16)
                    .frame(width: leftWidth, alignment: .leading)

                columnDivider

                OptionsBarMiddleColumn(model: model)
                    .padding(.horizontal, 16)
                    .frame(width: middleWidth, alignment: .leading)

                columnDivider

                OptionsBarRightColumn(model: model, canRecord: canRecord)
                    .frame(width: rightWidth)
            }
            .frame(width: panelWidth, height: panelHeight)

            if let banner = permissionBanner ?? model.bannerMessage {
                OptionsBarPermissionFooter(model: model, banner: banner)
            }
        }
        .frame(width: panelWidth)
        .overlay(alignment: .topTrailing) {
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .help("Close")
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        // No outer padding — that left a gray halo around the glass inside the NSPanel.
        .gesture(WindowDragGesture())
        .preferredColorScheme(.dark)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private var canRecord: Bool {
        model.permissionState == .granted && !model.selectedSourceID.isEmpty
    }

    private var permissionBanner: String? {
        switch model.permissionState {
        case .needsGrant:
            return "Screen Recording access is required. Grant access, then relaunch if sources stay empty."
        case .needsRelaunch:
            return "Permission looks enabled but no sources appeared. Relaunch EggplantRecorder (closing the panel is not enough)."
        default:
            return nil
        }
    }
}
