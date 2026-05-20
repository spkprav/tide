import SwiftUI

struct ServicesLauncherButton: View {
    @Environment(ServiceSupervisor.self) private var supervisor
    @State private var showing = false
    @State private var hover = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(SwiftUI.Color.tnBg2)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(borderColor, lineWidth: 1)
                    )

                if supervisor.runningCount > 0 {
                    Text("\(supervisor.runningCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(SwiftUI.Color.tnGreen))
                        .overlay(Capsule().strokeBorder(SwiftUI.Color.tnBg2, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hover)
        .onHover { hover = $0 }
        .help("Services")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            ServicesPopover()
        }
    }

    private var borderColor: SwiftUI.Color {
        if supervisor.runningCount > 0 { return SwiftUI.Color.tnGreen.opacity(0.6) }
        if hover { return SwiftUI.Color.tnBlue.opacity(0.5) }
        return SwiftUI.Color.tnLine
    }
}
