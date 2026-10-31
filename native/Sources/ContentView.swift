//
//  ContentView.swift
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = DeviceModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                statusBanner
                directMonitorSection
                ioSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            footer
        }
        .frame(width: 540)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("TASCAM US-2x2 / US-4x4")
                    .font(.title3.weight(.semibold))
                Text("Settings Panel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.connected {
                    HStack(spacing: 14) {
                        detail("Device", model.modelName)
                        detail("Firmware", model.firmwareVersion)
                        detail("Sample Rate", model.sampleRate)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(model.connected ? "Connected" : "No Device")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
        }
        .padding(20)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusBanner: some View {
        if let error = model.errorMessage {
            banner(
                icon: "exclamationmark.triangle.fill",
                title: "Unable to communicate with the device",
                message: error,
                tint: .orange
            )
        } else if !model.connected {
            banner(
                icon: "cable.connector",
                title: "No device connected",
                message: "Connect a TASCAM US-2x2 or US-4x4 with a USB cable. "
                       + "The controls become available automatically.",
                tint: .secondary
            )
        }
    }

    private func banner(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: Direct monitor

    private var directMonitorSection: some View {
        GroupBox(label: sectionLabel("Direct Monitor Settings")) {
            VStack(spacing: 12) {
                ForEach(0..<model.pairs, id: \.self) { pair in
                    HStack(spacing: 14) {
                        Text(pairTitle(pair))
                            .font(.callout)
                            .frame(width: 74, alignment: .trailing)

                        Picker("", selection: directMonitorBinding(pair)) {
                            Text("Mono").tag(false)
                            Text("Stereo").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)

                        Spacer()
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!model.connected)
        }
    }

    // MARK: IO settings

    private var ioSection: some View {
        GroupBox(label: sectionLabel("IO Settings")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Audio Input ON")
                        .font(.callout)
                        .frame(width: 106, alignment: .trailing)

                    ForEach(0..<model.inputChannels, id: \.self) { channel in
                        Toggle("IN \(channel + 1)", isOn: inputBinding(channel))
                            .toggleStyle(.checkbox)
                    }

                    Spacer()
                }

                Divider()

                ForEach(0..<model.pairs, id: \.self) { pair in
                    HStack(spacing: 14) {
                        Text(lineOutputTitle(pair))
                            .font(.callout)
                            .frame(width: 120, alignment: .trailing)

                        Picker("", selection: lineOutputBinding(pair)) {
                            ForEach(Array(model.lineOutputOptions.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 210)

                        Spacer()
                    }
                }

                Divider()

                Toggle("Auto Power Save ON", isOn: autoPowerSaveBinding)
                    .toggleStyle(.checkbox)
                    .padding(.leading, 120)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!model.connected)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Native Apple silicon replacement")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Protocol: US-2x2 / US-4x4 vendor interface")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
    }

    private func pairTitle(_ pair: Int) -> String {
        pair == 0 ? "IN 1-2" : "IN 3-4"
    }

    private func lineOutputTitle(_ pair: Int) -> String {
        pair == 0 ? "LINE OUT 1-2 :" : "LINE OUT 3-4 :"
    }

    private func directMonitorBinding(_ pair: Int) -> Binding<Bool> {
        Binding(
            get: { pair < model.directMonitorStereo.count ? model.directMonitorStereo[pair] : false },
            set: { model.setDirectMonitor(pair: pair, stereo: $0) }
        )
    }

    private func inputBinding(_ channel: Int) -> Binding<Bool> {
        Binding(
            get: { channel < model.inputEnabled.count ? model.inputEnabled[channel] : false },
            set: { model.setAudioInput(channel: channel, enabled: $0) }
        )
    }

    private func lineOutputBinding(_ pair: Int) -> Binding<Int> {
        Binding(
            get: { pair < model.lineOutput.count ? model.lineOutput[pair] : 0 },
            set: { model.setLineOutput(pair: pair, route: $0) }
        )
    }

    private var autoPowerSaveBinding: Binding<Bool> {
        Binding(
            get: { model.autoPowerSave },
            set: { model.setAutoPowerSave($0) }
        )
    }
}
