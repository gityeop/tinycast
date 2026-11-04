import SwiftUI

struct MCPInstallPlanView: View {
    let plan: MCPInstallPlan
    let root: URL

    var body: some View {
        Section {
            LabeledContent("Installation folder", value: root.path).textSelection(.enabled)
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("\(index + 1). \(step.title)").font(.headline)
                    Text(step.kind == .service ? "Background service · port \(step.readyPort)" : "Run once")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(([step.command] + step.arguments).map {
                        MCPInstallPlan.shellQuote(MCPInstallPlan.resolve($0, root: root))
                    }.joined(separator: " "))
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Text("Working folder: " + MCPInstallPlan.folder(step.directory, root: root).path)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            LabeledContent("MCP working folder", value: MCPInstallPlan.folder(plan.directory, root: root).path)
                .textSelection(.enabled)
            ForEach(plan.blockers, id: \.self) { blocker in
                Label(blocker, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        } header: {
            Text("Installation plan")
        } footer: {
            Text("Approval runs these commands in order, starts the listed background services, then tests and registers MCP. "
                + "Required services start with MCP and stop when MCP is disabled or Oncast quits. "
                + "A failed step stops setup; completed files remain in this folder.")
        }
    }
}
