import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CortexFocusWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CortexTaskBoardAttributes.self) { context in
      TaskBoardView(state: context.state)
        .activityBackgroundTint(Color(red: 0.95, green: 0.97, blue: 0.93))
        .activitySystemActionForegroundColor(.black)
        .widgetURL(taskURL("view", context.state.visibleTasks.first))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) { TaskBoardView(state: context.state, dark: true) }
      } compactLeading: {
        Label("\(context.state.taskCount)", systemImage: "leaf.fill").font(.caption)
      } compactTrailing: {
        if let task = context.state.visibleTasks.first {
          if task.phase == "active" {
            Text(timerInterval: task.start...max(task.start, task.end), countsDown: true)
              .monospacedDigit().frame(width: 45)
          } else {
            Text(task.phase == "ready" ? "Ready" : task.phase == "pending" ? "Soon" : "Paused")
              .font(.caption)
          }
        }
      } minimal: {
        Image(systemName: "leaf.fill")
      }
      .widgetURL(taskURL("view", context.state.visibleTasks.first))
    }
  }
}

private struct TaskBoardView: View {
  let state: CortexTaskBoardAttributes.ContentState
  var dark = false
  private var ink: Color { dark ? .white : Color(red: 0.16, green: 0.29, blue: 0.21) }
  private var displayed: [CortexTaskBoardAttributes.TaskItem] {
    state.visibleTasks
  }
  private var paired: Bool { displayed.count > 1 }

  var body: some View {
    // 144 pt content + 8 pt top/bottom margins = the 160 pt system limit.
    // Two columns leave each button at least 44 x 44 pt on the owner's iPhone.
    HStack(alignment: .top, spacing: 8) {
      ForEach(displayed) { task in
        if task.id != displayed.first?.id {
          Rectangle().fill(ink.opacity(0.22)).frame(width: 1)
        }
        VStack(spacing: 5) {
          header(task)
          controls(task)
        }.frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 8)
    .frame(height: 160).foregroundStyle(ink)
  }

  private func header(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    HStack(spacing: 4) {
      if state.pageCount > 1 && task.id == displayed.first?.id { pageArrow(previous: true) }
      VStack(spacing: 5) {
        Link(destination: taskURL("view", task)) {
          Text(task.title).font(.system(size: paired ? 16 : 17, weight: .semibold))
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityLabel("Open task: \(task.title)").frame(height: 20)
        progress(task)
      }.frame(maxWidth: .infinity)
      if state.pageCount > 1 && task.id == displayed.last?.id { pageArrow(previous: false) }
    }.frame(height: 45)
  }

  private func pageArrow(previous: Bool) -> some View {
    let target = state.pageIndex + (previous ? -1 : 1)
    let available = target >= 0 && target < state.pageCount
    return pageButton(target, previous: previous)
      .disabled(!available).opacity(available ? 1 : 0.35)
      .accessibilityLabel(previous ? "Previous tasks" : "Next tasks")
      .accessibilityValue("Page \(state.pageIndex + 1) of \(state.pageCount)")
  }

  @ViewBuilder private func pageButton(_ target: Int, previous: Bool) -> some View {
    if #available(iOS 17.0, *) {
      Button(intent: CortexFocusPageIntent(target)) { pageFace(previous: previous) }
        .buttonStyle(.plain)
    } else {
      Link(destination: URL(string: "cortex://focus?action=page&page=\(target)")!) {
        pageFace(previous: previous)
      }
    }
  }

  private func pageFace(previous: Bool) -> some View {
    VStack(spacing: 1) {
      Image(systemName: previous ? "chevron.left" : "chevron.right")
        .font(.system(size: 18, weight: .semibold))
      if previous {
        Text("\(state.pageIndex + 1)/\(state.pageCount)")
          .font(.system(size: 11, weight: .medium)).monospacedDigit()
      }
    }
    .frame(width: 44, height: 44)
    .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
  }

  private func progress(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.08))
      if task.phase == "active" {
        ProgressView(
          timerInterval: task.start...max(task.start.addingTimeInterval(1), task.end),
          countsDown: true
        ).labelsHidden().tint(ink.opacity(0.3)).scaleEffect(x: 1, y: 5)
        Text(timerInterval: task.start...max(task.start, task.end), countsDown: true)
          .monospacedDigit().multilineTextAlignment(.center)
          .frame(maxWidth: .infinity).padding(.horizontal, 6)
          .accessibilityLabel("Remaining planned time for \(task.title)")
      } else {
        Text(
          task.phase == "ready"
            ? "Ready to start"
            : task.phase == "pending"
              ? "Upcoming" : task.phase == "postponed" ? "Postponed" : "Paused"
        )
        .accessibilityLabel("\(task.title): \(task.phase). Timer is stopped.")
      }
    }
    .font(.system(size: 14, weight: .semibold))
    .frame(height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
  }

  private func controls(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        direct(
          task.phase == "active"
            ? (paired ? "Done" : "Completed!")
            : ["pending", "ready"].contains(task.phase) ? "Start" : "Resume",
          task.phase == "active" ? "complete" : "begin", task, primary: true)
        Link(destination: taskURL("postpone", task)) {
          face("Postpone", symbol: paired ? "clock.arrow.circlepath" : nil)
        }
        .accessibilityLabel("Postpone \(task.title) and give a reason")
        if task.phase == "active" {
          direct("Pause", "pause", task, symbol: "pause.fill")
        } else {
          Link(destination: taskURL("view", task)) { face("More", symbol: "ellipsis") }
            .accessibilityLabel("More controls for \(task.title)")
        }
      }
      if task.phase == "active" {
        HStack(spacing: 6) { extensions(task) }
      } else {
        Group {
          if ["pending", "ready"].contains(task.phase) {
            HStack(spacing: 3) {
              Text("Planned")
              Text(task.start, style: .time)
            }
          } else {
            Text("Still here. Resume when you’re ready.")
          }
        }
        .font(.system(size: 14)).foregroundStyle(ink.opacity(0.75))
        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
      }
    }.font(.system(size: paired ? 15 : 16, weight: .semibold))
  }

  private func extensions(_ task: CortexTaskBoardAttributes.TaskItem) -> some View {
    ForEach([5, 10, 15], id: \.self) { minutes in
      direct(
        paired ? "+\(minutes)" : "+\(minutes) min", "extend", task, minutes: minutes)
    }
  }

  private func face(_ title: String, symbol: String? = nil, primary: Bool = false) -> some View {
    Group {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
      } else {
        Text(title).lineLimit(1).minimumScaleFactor(0.8)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
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
