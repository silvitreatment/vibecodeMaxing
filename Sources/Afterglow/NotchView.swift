import SwiftUI

private let mint = Color(red: 0.65, green: 0.95, blue: 0.77)
private let lavender = Color(red: 0.74, green: 0.68, blue: 1)

struct NotchView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                notchBar
                if model.expanded || model.expansionProgress > 0 {
                    content
                        .frame(width: 264)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(max(0, (model.expansionProgress - 0.2) / 0.8))
                        .allowsHitTesting(model.expanded)
                }
            }
            .padding(.top, model.topOverflow)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background {
                ZStack {
                    glassSurface.opacity(model.expansionProgress)
                    Color.black.opacity(1 - model.expansionProgress)
                }
            }
            .clipShape(surfaceShape)
            .overlay(alignment: .top) {
                Color.black.frame(height: model.topOverflow)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .environment(\.appearsActive, true)
        .transaction { $0.disablesAnimations = true }
        .onExitCommand { model.setExpanded(false) }
    }

    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 9 + 11 * model.expansionProgress,
                               bottomTrailingRadius: 9 + 11 * model.expansionProgress, topTrailingRadius: 0)
    }

    @ViewBuilder private var glassSurface: some View {
        if #available(macOS 26.0, *), !CommandLine.arguments.contains("--snapshot") {
            Color.clear.glassEffect(.clear, in: surfaceShape)
        } else {
            surfaceShape.fill(.ultraThinMaterial)
        }
    }

    private var notchBar: some View {
        Button { model.setExpanded(!model.expanded) } label: {
            HStack(spacing: 0) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(model.isActive ? mint : lavender)
                    .frame(minWidth: 0, maxWidth: .infinity)
                Color.clear.frame(width: model.notchWidth).allowsHitTesting(false)
                HStack(spacing: 3) {
                    Image(systemName: batterySymbol)
                    Text(model.battery.percent.map { "\($0)%" } ?? "—")
                        .monospacedDigit()
                }
                .fixedSize()
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(minWidth: 0, maxWidth: .infinity)
                .opacity(model.expansionProgress)
                .clipped()
            }
            .frame(height: model.notchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.expanded ? "Collapse Afterglow" : "Open Afterglow")
        .accessibilityValue(model.expanded ? (model.battery.percent.map { "Battery: \($0)%" } ?? "Battery unavailable") : "")
        .help(model.expanded ? (model.battery.percent.map { "Battery: \($0)%" } ?? "Battery unavailable") : "Open Afterglow")
    }

    private var batterySymbol: String {
        guard model.battery.onBattery else { return "bolt.fill" }
        switch model.battery.percent ?? 0 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.isActive ? "Remaining" : "Keep awake", systemImage: "clock")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if model.isActive {
                    Text(model.remaining)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green).monospacedDigit()
                } else {
                    Picker("Duration", selection: $model.duration) {
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                        Text("8 hours").tag(480)
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.mini).fixedSize()
                    .disabled(model.isBusy)
                }
            }
            .frame(height: 18)

            actionButton

            if let message = model.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9))
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .help(message).textSelection(.enabled)
            }

        }
        .padding(.top, 10).padding(.bottom, 16)
    }

    @ViewBuilder private var actionButton: some View {
        if #available(macOS 26.0, *), !CommandLine.arguments.contains("--snapshot") {
            sessionButton.buttonStyle(.glassProminent)
                .tint(model.isActive ? mint : .white)
                .buttonBorderShape(.roundedRectangle(radius: 10))
        } else {
            sessionButton.buttonStyle(.plain)
                .background(model.isActive ? mint : .white, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var sessionButton: some View {
        Button(action: model.toggle) {
            HStack(spacing: 6) {
                if model.isBusy { ProgressView().controlSize(.mini).tint(.black) }
                else { Image(systemName: model.isActive ? "stop.fill" : "power") }
                Text(buttonTitle)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black.opacity(0.9))
            .frame(maxWidth: .infinity).frame(height: 32)
        }
        .disabled(model.isBusy)
        .keyboardShortcut(.return, modifiers: [])
    }

    private var buttonTitle: String {
        switch model.phase {
        case .idle: return "Keep agents running"
        case .authorizing: return "Approve in macOS…"
        case .active: return "End session"
        case .stopping: return "Finishing up…"
        }
    }
}
