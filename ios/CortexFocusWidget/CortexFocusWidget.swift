import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CortexFocusWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CortexFocusAttributes.self) { context in
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("Cortex · Current task", systemImage: "leaf.fill").font(.caption)
          Spacer()
          Text(context.attributes.startedAt, style: .timer).monospacedDigit().font(.caption)
        }.foregroundStyle(Color(red: 0.20, green: 0.32, blue: 0.25))
        Text(context.attributes.title).font(.headline).lineLimit(2)
        Text(
          context.isStale
            ? "Still unconfirmed. Open Cortex to refresh check-ins."
            : "One thing at a time. You can take a break."
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 18) {
          action("Done", "checkmark.circle", "complete", context)
          action("Still working", "clock.arrow.circlepath", "extend", context)
          action("Break", "pause.circle", "pause", context)
        }.font(.caption.weight(.semibold))
      }.padding(16)
        .activityBackgroundTint(Color(red: 0.95, green: 0.97, blue: 0.93))
        .activitySystemActionForegroundColor(.black)
        .widgetURL(url("view", context))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Image(systemName: "leaf.fill") }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.attributes.startedAt, style: .timer).monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 10) {
            Text(context.attributes.title).font(.headline).lineLimit(1)
            HStack {
              action("Done", "checkmark.circle", "complete", context)
              Spacer()
              action("More time", "clock", "extend", context)
              Spacer()
              action("Break", "pause.circle", "pause", context)
            }.font(.caption)
          }
        }
      } compactLeading: {
        Image(systemName: "leaf.fill")
      } compactTrailing: {
        Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 48)
      } minimal: {
        Image(systemName: "leaf.fill")
      }
      .widgetURL(url("view", context))
    }
  }
  func url(_ action: String, _ context: ActivityViewContext<CortexFocusAttributes>) -> URL {
    var c = URLComponents()
    c.scheme = "cortex"
    c.host = "focus"
    c.queryItems = [
      URLQueryItem(name: "id", value: context.attributes.id),
      URLQueryItem(name: "revision", value: String(context.state.revision)),
      URLQueryItem(name: "action", value: action),
    ]
    return c.url!
  }
  func action(
    _ title: String, _ icon: String, _ action: String,
    _ context: ActivityViewContext<CortexFocusAttributes>
  ) -> some View {
    Link(destination: url(action, context)) { Label(title, systemImage: icon) }
      .foregroundStyle(Color(red: 0.16, green: 0.29, blue: 0.21))
  }
}
