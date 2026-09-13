import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CortexFocusWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CortexTaskBoardAttributes.self) { context in
      TaskBoardView(state: context.state)
        .padding(12)
        .activityBackgroundTint(Color(red: 0.95, green: 0.97, blue: 0.93))
        .activitySystemActionForegroundColor(.black)
        .widgetURL(taskURL("view", context.state.tasks.first))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) { TaskBoardView(state: context.state, dark: true) }
      } compactLeading: {
        Label("\(context.state.tasks.count)", systemImage: "leaf.fill").font(.caption)
      } compactTrailing: {
        if let task = context.state.tasks.first {
          if task.status == "active" {
            Text(timerInterval: task.start...max(task.start, task.end), countsDown: true)
              .monospacedDigit().frame(width: 45)
          } else {
            Text("Ready").font(.caption)
          }
        }
      } minimal: {
        Image(systemName: "leaf.fill")
      }
      .widgetURL(taskURL("view", context.state.tasks.first))
    }
  }
}

private struct TaskBoardView: View {
  let state: CortexTaskBoardAttributes.ContentState
  var dark = false
  private var ink: Color { dark ? .white : Color(red: 0.16, green: 0.29, blue: 0.21) }
  private var selected: CortexTaskBoardAttributes.TaskItem? {
    state.tasks.first { $0.id == state.selectedID } ?? state.tasks.first
  }
  private var displayed: [CortexTaskBoardAttributes.TaskItem] {
    var list = Array(state.tasks.prefix(2))
    if let selected, !list.contains(where: { $0.id == selected.id }) {
      list = [selected] + list.prefix(1)
    }
    return list
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label(
          state.tasks.allSatisfy(\.preview) ? "Cortex · Preview" : "Cortex · Your tasks",
          systemImage: "leaf.fill")
        Spacer()
        if state.tasks.count > 2 {
          Link("+\(state.tasks.count - 2) in app", destination: taskURL("view", selected))
        }
      }.font(.caption2).foregroundStyle(ink.opacity(0.7))
      ForEach(displayed) { task in
        VStack(spacing: 3) {
          HStack(spacing: 6) {
            select(task)
            Spacer(minLength: 4)
            if task.status == "active" {
              Text(timerInterval: task.start...max(task.start, task.end), countsDown: true)
                .monospacedDigit().frame(width: 52, alignment: .trailing).font(.caption)
            } else {
              Text("Ready").font(.caption)
            }
          }
          if task.status == "active" {
            ProgressView(
              timerInterval: task.start...max(task.start.addingTimeInterval(1), task.end),
              countsDown: true
            ).tint(ink)
              .labelsHidden().accessibilityLabel("Remaining planned time for \(task.title)")
          }
        }
      }
      if let task = selected {
        HStack(spacing: 8) {
          direct(
            task.status == "ready" ? "I’ve started" : "Completed!",
            task.status == "ready" ? "begin" : "complete", task)
          Spacer(minLength: 0)
          Link("Postpone", destination: taskURL("postpone", task)).padding(.vertical, 5)
          if task.status == "active" { direct("Break", "pause", task) }
        }.font(.caption.weight(.semibold))
        if task.status == "active" {
          HStack(spacing: 8) {
            ForEach([5, 10, 15], id: \.self) { minutes in
              direct("+\(minutes) min", "extend", task, minutes: minutes).frame(maxWidth: .infinity)
            }
          }.font(.caption.weight(.semibold))
        }
      }
    }.foregroundStyle(ink)
  }
  @ViewBuilder private func select(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    if #available(iOS 17.0, *) {
      Button(intent: CortexFocusActionIntent(task.id, task.revision, "select")) {
        HStack(spacing: 4) {
          Image(systemName: task.id == selected?.id ? "circle.inset.filled" : "circle").font(
            .caption2)
          Text(task.title).lineLimit(1).font(.caption.weight(.semibold))
        }
      }.buttonStyle(.plain).accessibilityLabel("Select \(task.title)")
    } else {
      Text(task.title).font(.caption.weight(.semibold)).lineLimit(1)
    }
  }
  @ViewBuilder private func direct(
    _ title: String, _ action: String, _ task: CortexTaskBoardAttributes.TaskItem, minutes: Int = 15
  ) -> some View {
    if #available(iOS 17.0, *) {
      Button(intent: CortexFocusActionIntent(task.id, task.revision, action, minutes: minutes)) {
        Text(title).padding(.horizontal, 8).padding(.vertical, 5)
      }
      .buttonStyle(.plain).background(ink.opacity(0.09), in: Capsule())
      .accessibilityLabel("\(title) for \(task.title)")
    } else {
      Link(title, destination: taskURL(action, task, minutes: minutes))
    }
  }
}
private func taskURL(
  _ action: String, _ task: CortexTaskBoardAttributes.TaskItem?, minutes: Int = 15
) -> URL {
  var c = URLComponents()
  c.scheme = "cortex"
  c.host = "focus"
  c.queryItems = [
    URLQueryItem(name: "id", value: task?.id ?? ""),
    URLQueryItem(name: "revision", value: String(task?.revision ?? -1)),
    URLQueryItem(name: "action", value: action),
    URLQueryItem(name: "minutes", value: String(minutes)),
  ]
  return c.url!
}
