import SwiftUI

struct ServicesPopover: View {
    @Environment(ServiceStore.self) private var store
    @Environment(ServiceSupervisor.self) private var supervisor
    @Environment(ProjectStore.self) private var projectStore

    @State private var editing: Service?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(SwiftUI.Color.tnLine).frame(height: 1)
            content
        }
        .frame(width: 380, height: 480)
        .background(SwiftUI.Color.tnBg2)
        .sheet(isPresented: $creating) {
            ServiceEditorSheet(editing: nil, defaultCwd: defaultCwd) { svc in
                store.upsert(svc)
                supervisor.notifyServicesChanged()
            }
        }
        .sheet(item: $editing) { svc in
            ServiceEditorSheet(editing: svc, defaultCwd: defaultCwd) { updated in
                store.upsert(updated)
                supervisor.notifyServicesChanged()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SwiftUI.Color.tnBlue)
            Text("Services")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg)
            if supervisor.runningCount > 0 {
                Text("\(supervisor.runningCount) running")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SwiftUI.Color.tnGreen)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(SwiftUI.Color.tnGreen.opacity(0.12)))
            }
            Spacer()
            Button {
                creating = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(TideChipButton(tint: SwiftUI.Color.tnBlue))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if store.services.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.services) { service in
                        ServiceCard(
                            service: service,
                            runner: supervisor.runner(for: service),
                            onEdit: { editing = service },
                            onDelete: { delete(service) }
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SwiftUI.Color.tnFg3)
            Text("No services yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg2)
            Text("Add a command tied to a folder — start, stop,\nand monitor pid + port from one place.")
                .font(.system(size: 11))
                .foregroundStyle(SwiftUI.Color.tnFg3)
                .multilineTextAlignment(.center)
            Button {
                creating = true
            } label: {
                Label("Add a service", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(TidePrimaryButton())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var defaultCwd: String {
        if let p = projectStore.selected { return p.path }
        return NSHomeDirectory()
    }

    private func delete(_ service: Service) {
        supervisor.discardRunner(serviceID: service.id)
        store.remove(id: service.id)
    }
}
