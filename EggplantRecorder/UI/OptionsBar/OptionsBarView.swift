import SwiftUI

struct OptionsBarView: View {
    @ObservedObject var model: OptionsBarModel

    /// Solid tool panel — between old OMI and the over-tight pass: 224 + 224 + 76.
    private let leftWidth: CGFloat = 224
    private let middleWidth: CGFloat = 224
    private let rightWidth: CGFloat = 76
    private let panelHeight: CGFloat = 186
    private let cornerRadius: CGFloat = 8

    private var panelWidth: CGFloat { leftWidth + middleWidth + rightWidth + 2 }

    /// Style B: opaque charcoal, no glass blur.
    private let panelFill = Color(red: 0.173, green: 0.180, blue: 0.200) // #2c2e33
    private let dividerFill = Color(red: 0.227, green: 0.239, blue: 0.267) // #3a3d44

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                OptionsBarLeftColumn(model: model)
                    .padding(.horizontal, 14)
                    .frame(width: leftWidth, alignment: .leading)

                columnDivider

                OptionsBarMiddleColumn(model: model)
                    .padding(.horizontal, 14)
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
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .help("Close")
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .gesture(WindowDragGesture())
        .preferredColorScheme(.dark)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(dividerFill)
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    private var canRecord: Bool {
        model.permissionState == .granted && !model.selectedSourceID.isEmpty && !model.isBusy
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
