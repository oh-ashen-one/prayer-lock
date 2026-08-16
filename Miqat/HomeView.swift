import SwiftUI

/// The home of the chapel: a Canvas lamp clock above the kept alarms,
/// with the plus that lights a new one. When an alarm's moment arrives and
/// its lock is armed, the full-screen LockChapelView takes over. The first
/// time in, OnboardingView walks the rite; the vestry is reached from here.
struct HomeView: View {
    @State private var alarmsData: Data = (try? JSONEncoder().encode(LampStore.load())) ?? Data()
    @State private var showingNewAlarm = false
    @State private var firingAlarm: LampAlarm?
    @State private var showingVestry = false
    @State private var showOnboarding: Bool = { !ChapelSettingsStore.hasOnboarded }()

    private var alarms: [LampAlarm] {
        (try? JSONDecoder().decode([LampAlarm].self, from: alarmsData)) ?? []
    }

    private var nextLightText: String {
        let now = Date()
        guard let soonest = alarms.filter(\.enabled).compactMap { $0.nextFire(after: now) }.min() else {
            return "no light is set"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "next light \(formatter.string(from: soonest))"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ChapelTheme.Background()

            VStack(spacing: 26) {
                Spacer().frame(height: 8)

                HStack(spacing: 14) {
                    Text("MIQAT")
                        .chapelLabel(15, weight: .medium)
                        .foregroundStyle(ChapelTheme.brass)

                    Spacer()

                    Button {
                        showingVestry = true
                    } label: {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 14))
                            .foregroundStyle(ChapelTheme.brassDim)
                    }
                    .buttonStyle(.plain)
                }

                Text("the appointed boundary")
                    .chapelLabel(10, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.8))

                ChapelTheme.ChapelGeometry.hairlineRule(width: 56)

                LampClockView()
                    .frame(height: 210)

                Text(nextLightText)
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim)

                alarmList

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)

            addButton
        }
        // The lock chapel: no dismiss gesture, the rite or the emergency exit.
        .fullScreenCover(item: $firingAlarm) { alarm in
            LockChapelView(alarm: alarm)
                .ignoresSafeArea()
        }
        // The first-arrival rite, walked once.
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .onDisappear { showOnboarding = false }
        }
        .sheet(isPresented: $showingVestry) {
            VestryView()
        }
        .sheet(isPresented: $showingNewAlarm) {
            AlarmEditorView(alarm: nil)
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { now in
            checkForFiring(alarmAt: now)
        }
    }

    // MARK: Alarm list

    private var alarmList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KEPT LIGHTS")
                    .chapelLabel(10, weight: .medium)
                    .foregroundStyle(ChapelTheme.dim)
                Spacer()
            }

            if alarms.isEmpty {
                Text("none yet")
                    .chapelLabel(12, weight: .regular)
                    .foregroundStyle(ChapelTheme.dim.opacity(0.7))
            } else {
                ForEach(alarms) { alarm in
                    Button {
                        showingNewAlarm = true
                    } label: {
                        alarmRow(alarm)
                    }
                    .buttonStyle(.plain)
                    .chapelCard()
                }

                Button {
                    fireNextLightForPreview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flame")
                            .font(.system(size: 11))
                        Text("light the next one now")
                            .chapelLabel(10, weight: .regular)
                    }
                    .foregroundStyle(ChapelTheme.brassDim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func alarmRow(_ alarm: LampAlarm) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(alarm.enabled ? ChapelTheme.flame : ChapelTheme.stoneLit)
                    .frame(width: 7, height: 7)

                Text(alarm.label.isEmpty ? "The lamp" : alarm.label)
                    .chapelLabel(14, weight: .regular)
                    .foregroundStyle(alarm.enabled ? ChapelTheme.text : ChapelTheme.dim)

                Spacer()

                Text(alarm.formattedTime)
                    .font(ChapelTheme.display(16, weight: .regular))
                    .foregroundStyle(alarm.enabled ? ChapelTheme.brass : ChapelTheme.dim)

                Button {
                    toggleAlarm(alarm.id)
                } label: {
                    Image(systemName: alarm.enabled ? "flame.fill" : "flame")
                        .font(.system(size: 13))
                        .foregroundStyle(alarm.enabled ? ChapelTheme.flame : ChapelTheme.dim)
                }
            }

            Text("\(alarm.repeatSummary) · \(alarm.prayerPack.label)\(alarm.recitationEnabled ? " · recited" : "")\(alarm.sealPackEnabled ? " · sealed" : "")")
                .chapelLabel(10, weight: .regular)
                .foregroundStyle(ChapelTheme.dim.opacity(0.75))
        }
    }

    private var addButton: some View {
        Button {
            showingNewAlarm = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ChapelTheme.well)
                .frame(width: 52, height: 52)
                .background(Circle().fill(ChapelTheme.brass))
        }
        .padding(.trailing, 28)
        .padding(.bottom, 30)
    }

    private func toggleAlarm(_ id: UUID) {
        var list = alarms
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].enabled.toggle()
        alarmsData = (try? JSONEncoder().encode(list)) ?? Data()
    }

    // MARK: Firing

    /// When a kept light's moment passes while the app is awake, open its
    /// lock chapel. One-shot lights rest after they fire; repeating lights
    /// keep their place and return on the next matching day.
    private func checkForFiring(alarmAt now: Date) {
        guard firingAlarm == nil else { return }
        for alarm in alarms where alarm.enabled {
            guard let fire = alarm.nextFire(after: now.addingTimeInterval(-90)),
                  fire <= now else { continue }
            firingAlarm = alarm
            if alarm.isOneShot {
                var list = alarms
                if let index = list.firstIndex(where: { $0.id == alarm.id }) {
                    list[index].enabled = false
                    alarmsData = (try? JSONEncoder().encode(list)) ?? Data()
                }
            }
            return
        }
    }

    /// The preview handle: light the soonest kept one now, so the chapel can
    /// be walked without waiting for its hour.
    private func fireNextLightForPreview() {
        guard firingAlarm == nil, let soonest = alarms.filter(\.enabled).min(by: {
            ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute)
        }) else { return }
        firingAlarm = soonest
    }
}

// MARK: - Lamp clock (Canvas)

/// The home's heart: a Canvas-drawn oil-lamp face. Brass ring, square
/// hour marks (Song geometry), gold hands, and a small wick flame at the
/// center that does not tick.
struct LampClockView: View {
    @State private var now = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let date = context.date
            Canvas { graphContext, size in
                draw(in: &graphContext, size: size, date: date)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        // Ring: the lamp's brass rim.
        let ring = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(ring, with: .color(ChapelTheme.brass.opacity(0.85)), lineWidth: 2)
        context.stroke(
            ring.strokedPath(StrokeStyle(lineWidth: 2)).offsetBy(dx: 0, dy: 0),
            with: .color(ChapelTheme.well.opacity(1)),
            lineWidth: 0.5
        )

        // Hour marks: small squares, the Song-geometry accent.
        let markSize = radius * 0.10
        for tick in 0..<60 {
            let angle = Double(tick) / 60 * 2 * .pi - .pi / 2
            let isHour = tick % 5 == 0
            let inset = radius * (isHour ? 0.86 : 0.92)
            let point = CGPoint(
                x: center.x + cos(angle) * inset,
                y: center.y + sin(angle) * inset
            )
            let s = isHour ? markSize : markSize * 0.45
            let rect = CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)
            let color = isHour ? ChapelTheme.brass : ChapelTheme.hairline.opacity(0.8)
            context.fill(Path(rect), with: .color(color))
        }

        // Hands.
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let second = Double(components.second ?? 0) + (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1))
        let minute = Double(components.minute ?? 0) + second / 60
        let hour = (Double(components.hour ?? 0) + minute / 60).truncatingRemainder(dividingBy: 12)

        drawHand(
            in: &context, center: center, radius: radius * 0.52,
            angle: hour / 12 * 2 * .pi - .pi / 2,
            color: ChapelTheme.brass, width: 4, cap: .butt
        )
        drawHand(
            in: &context, center: center, radius: radius * 0.74,
            angle: minute / 60 * 2 * .pi - .pi / 2,
            color: ChapelTheme.flame.opacity(0.9), width: 2.5, cap: .butt
        )

        // Wick: a small flame at the hub, plus its core.
        let wick = Path(ellipseIn: CGRect(
            x: center.x - radius * 0.05, y: center.y - radius * 0.07,
            width: radius * 0.10, height: radius * 0.14
        ))
        context.fill(wick, with: .color(ChapelTheme.ember.opacity(0.9)))
        let core = Path(ellipseIn: CGRect(
            x: center.x - radius * 0.02, y: center.y - radius * 0.035,
            width: radius * 0.04, height: radius * 0.07
        ))
        context.fill(core, with: .color(ChapelTheme.flameCore))
    }

    private func drawHand(
        in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
        angle: Double, color: Color, width: CGFloat, cap: CGLineCap
    ) {
        var path = Path()
        // A short tail behind the hub, then out to the tip.
        path.move(to: CGPoint(
            x: center.x - cos(angle) * radius * 0.18,
            y: center.y - sin(angle) * radius * 0.18
        ))
        path.addLine(to: CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        ))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: cap)
        )
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
