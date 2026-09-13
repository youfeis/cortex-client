import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CortexFocusWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CortexTaskBoardAttributes.self) { context in
      TaskBoardView(state: context.state)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
  private var displayed: [CortexTaskBoardAttributes.TaskItem] {
    Array(state.tasks.prefix(2))
  }
  private var compact: Bool { displayed.count > 1 }

  var body: some View {
    // iOS may truncate Lock Screen activities above 160 pt. Two rows use the
    // available height for independent controls instead of a shared selection.
    VStack(alignment: .leading, spacing: compact ? 3 : 6) {
      ForEach(displayed) { task in
        if task.id != displayed.first?.id {
          Divider().overlay(ink.opacity(0.15))
        }
        VStack(alignment: .leading, spacing: compact ? 3 : 7) {
          HStack(spacing: 6) {
            Text(task.title)
              .font(.system(size: compact ? 13 : 15, weight: .semibold))
              .lineLimit(1)
            Spacer(minLength: 4)
            if task.id == displayed.first?.id && state.tasks.count > 2 {
              Link("+\(state.tasks.count - 2) in app", destination: taskURL("view", task))
                .font(.system(size: 11, weight: .semibold))
                .accessibilityLabel("Show all \(state.tasks.count) tasks in Cortex")
            }
            if task.status == "active" {
              Text(timerInterval: task.start...max(task.start, task.end), countsDown: true)
                .monospacedDigit().frame(width: 52, alignment: .trailing)
                .font(.system(size: compact ? 12 : 14, weight: .medium))
            } else {
              Text("Ready").font(.system(size: compact ? 12 : 14))
            }
          }
          progress(task)
          controls(task)
        }
      }
    }.foregroundStyle(ink)
  }

  private func progress(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    Group {
      if task.status == "active" {
        ProgressView(
          timerInterval: task.start...max(task.start.addingTimeInterval(1), task.end),
          countsDown: true
        ).labelsHidden()
          .accessibilityLabel("Remaining planned time for \(task.title)")
      } else {
        ProgressView(value: 1, total: 1)
          .accessibilityLabel("\(task.title) is ready; timer has not started")
      }
    }
    .tint(task.status == "active" ? ink : ink.opacity(0.3))
    .scaleEffect(x: 1, y: compact ? 1.5 : 2)
    .frame(height: compact ? 6 : 8)
  }

  private func controls(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    VStack(spacing: 7) {
      HStack(spacing: compact ? 4 : 7) {
        direct(
          task.status == "ready" ? "I’ve started" : "Completed!",
          task.status == "ready" ? "begin" : "complete", task, primary: true)
        if compact && task.status == "active" { extensions(task) }
        Link(destination: taskURL("postpone", task)) { face("Postpone") }
          .accessibilityLabel("Postpone \(task.title) and give a reason")
        if task.status == "active" { direct("Break", "pause", task, symbol: "pause.fill") }
      }
      if !compact && task.status == "active" {
        HStack(spacing: 7) { extensions(task) }
      }
    }.font(.system(size: compact ? 11 : 13, weight: .semibold))
  }

  private func extensions(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    ForEach([5, 10, 15], id: \.self) { minutes in
      direct(
        compact ? "+\(minutes)" : "+\(minutes) min", "extend", task, minutes: minutes)
    }
  }

  private func face(_ title: String, symbol: String? = nil, primary: Bool = false) -> some View {
    Group {
      if let symbol {
        Image(systemName: symbol).frame(width: compact ? 28 : 40)
      } else {
        Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
          .padding(.horizontal, compact ? 6 : 10).frame(maxWidth: .infinity)
      }
    }
    .frame(height: compact ? 34 : 38)
    .foregroundStyle(primary ? (dark ? Color.black : Color.white) : ink)
    .background(primary ? ink : ink.opacity(0.09), in: Capsule())
    .contentShape(Capsule())
  }

  @ViewBuilder private func direct(
    _ title: String, _ action: String, _ task: CortexTaskBoardAttributes.TaskItem,
    minutes: Int = 15, primary: Bool = false, symbol: String? = nil
  ) -> some View {
    if #available(iOS 17.0, *) {
      Button(intent: CortexFocusActionIntent(task.id, task.revision, action, minutes: minutes)) {
        face(title, symbol: symbol, primary: primary)
      }.buttonStyle(.plain)
        .accessibilityLabel(
          action == "extend"
            ? "Add \(minutes) minutes to \(task.title)" : "\(title) for \(task.title)")
    } else {
      Link(destination: taskURL(action, task, minutes: minutes)) {
        face(title, symbol: symbol, primary: primary)
      }
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
