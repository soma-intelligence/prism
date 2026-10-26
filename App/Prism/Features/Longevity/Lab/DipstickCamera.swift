//
//  DipstickCamera.swift
//  Prism
//
//  The camera for a urine strip: the live picture with a slot drawn over it
//  (the white handle at the leading end, a tick and a name for each of the
//  ten pads), a shutter, and the photo cropped to that slot. The reader
//  samples the crop with the same layout the slot is drawn from
//  (`UrineStripLayout`), so what the person lines up is what is read.
//
//  The system camera sheet can't draw that slot where the photo is taken,
//  so this runs its own capture session. iPhone and iPad only; elsewhere the
//  sheet offers a photo cropped to the strip.
//

import SwiftUI
import SomaUI

/// The slot's shape: long and thin like a strip, a little taller than one so
/// a hand can hold it inside.
nonisolated enum DipstickGuide {
    /// Width over height of the slot.
    static let aspect: CGFloat = 12
    /// The slot's width as a share of the picture's.
    static let widthShare: CGFloat = 0.9
}

/// The slot itself: the handle's box, ten pad ticks, their names, and the
/// line the strip's middle goes on. Drawn over the camera, and in the sheet
/// as the picture of what to do.
struct DipstickGuideOverlay: View {
    var reversed = false
    var showsNames = true

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let layout = UrineStripLayout.standard
        let names = UrineCatalog.padOrder.compactMap { UrineCatalog.marker(id: $0)?.name }
        let order = reversed ? Array(names.reversed()) : names
        GeometryReader { proxy in
            let size = proxy.size
            let line = theme.colors.inkPrimary.color
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: theme.metrics.spaceXS, style: .continuous)
                    .strokeBorder(line, lineWidth: 1.5)
                // The handle.
                Rectangle()
                    .strokeBorder(line.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: size.width * (layout.handle.upperBound - layout.handle.lowerBound), height: size.height * 0.6)
                    .offset(x: size.width * layout.handle.lowerBound, y: size.height * 0.2)
                // The strip's middle.
                Rectangle()
                    .fill(line.opacity(0.5))
                    .frame(width: size.width * (layout.pads.upperBound - layout.handle.lowerBound), height: 0.5)
                    .offset(x: size.width * layout.handle.lowerBound, y: size.height / 2)
                ForEach(0..<layout.count, id: \.self) { index in
                    let x = size.width * layout.centre(index)
                    let box = size.width * layout.pitch * layout.sampleWidth
                    Rectangle()
                        .strokeBorder(line, lineWidth: 1)
                        .frame(width: box, height: size.height * (layout.sampleHeight.upperBound - layout.sampleHeight.lowerBound))
                        .offset(x: x - box / 2, y: size.height * layout.sampleHeight.lowerBound)
                    if showsNames, index < order.count {
                        Text(order[index])
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(line)
                            .lineLimit(1)
                            .fixedSize()
                            .rotationEffect(.degrees(-60), anchor: .bottomLeading)
                            .offset(x: x, y: -theme.metrics.spaceM)
                    }
                }
            }
        }
        .aspectRatio(DipstickGuide.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#if os(iOS)
import AVFoundation
import UIKit

/// The live strip camera. Hands back the photo cropped to the slot, upright,
/// or nil when the person cancels or the camera is not there.
struct DipstickCamera: View {
    let onFinish: (CGImage?) -> Void

    @Environment(\.somaTheme) private var theme
    @State private var camera = DipstickCameraSession()
    @State private var layerSize: CGSize = .zero
    @State private var isTaking = false

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        ZStack {
            // The picture and the slot share one frame, the whole screen, so
            // the slot maps back onto the photo.
            GeometryReader { proxy in
                let slot = Self.slot(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    DipstickPreview(session: camera.session)
                    DipstickGuideOverlay()
                        .frame(width: slot.width, height: slot.height)
                        .offset(x: slot.minX, y: slot.minY)
                }
                .onAppear { layerSize = proxy.size }
                .onChange(of: proxy.size) { layerSize = proxy.size }
            }
            .ignoresSafeArea()

            VStack(spacing: metrics.cardSpacing) {
                Text("Lay the strip on white paper, handle on the left, and line each pad up with its box.")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, metrics.pagePadding)
                Text("Daylight, no flash, one to two minutes after dipping.")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                Spacer()
                HStack {
                    Button("Cancel") { camera.stop(); onFinish(nil) }
                        .somaFont(theme.typography.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .frame(maxWidth: .infinity)
                    SomaShutterButton(state: .ready, dimmed: !camera.isRunning || isTaking, accessibilityLabel: "Read the strip") {
                        guard camera.isRunning, !isTaking else { return }
                        isTaking = true
                        let size = layerSize
                        Task {
                            let photo = await camera.capture()
                            camera.stop()
                            onFinish(photo.flatMap { DipstickCrop.crop($0, slot: Self.slot(in: size), in: size) })
                        }
                    }
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
                .padding(.bottom, metrics.pagePadding)
            }
            .padding(.top, metrics.pagePadding)
        }
        .background(colors.canvas.color.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    /// The slot across the middle of the screen.
    static func slot(in size: CGSize) -> CGRect {
        let width = size.width * DipstickGuide.widthShare
        let height = width / DipstickGuide.aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// The photo cropped to the slot. The preview fills the screen and keeps
/// the photo's shape, so the slot maps back by the same scale and offset.
nonisolated enum DipstickCrop {
    static func crop(_ image: CGImage, slot: CGRect, in view: CGSize) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0, view.width > 0, view.height > 0 else { return nil }
        let scale = max(view.width / w, view.height / h)
        let offsetX = (view.width - w * scale) / 2, offsetY = (view.height - h * scale) / 2
        let rect = CGRect(x: (slot.minX - offsetX) / scale, y: (slot.minY - offsetY) / scale,
                          width: slot.width / scale, height: slot.height / scale)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isNull, rect.width > 4, rect.height > 2 else { return nil }
        return image.cropping(to: rect.integral)
    }
}

/// The capture session behind the strip camera: the back wide camera, one
/// photo output, started and stopped off the main thread.
@MainActor
@Observable
final class DipstickCameraSession {
    nonisolated let session = AVCaptureSession()
    private nonisolated let output = AVCapturePhotoOutput()
    private(set) var isRunning = false
    private var delegate: DipstickPhotoDelegate?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        let session = session, output = output
        let running = await Task.detached(priority: .userInitiated) { () -> Bool in
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.inputs.isEmpty,
               let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.outputs.isEmpty, session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            session.startRunning()
            return session.isRunning
        }.value
        isRunning = running
    }

    func stop() {
        let session = session
        isRunning = false
        Task.detached { session.stopRunning() }
    }

    /// One photo, upright.
    func capture() async -> CGImage? {
        guard isRunning else { return nil }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return await withCheckedContinuation { continuation in
            let delegate = DipstickPhotoDelegate { data in
                continuation.resume(returning: data.flatMap(DipstickPhotoDelegate.upright))
            }
            self.delegate = delegate
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

nonisolated final class DipstickPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let done: (Data?) -> Void

    init(done: @escaping (Data?) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        done(error == nil ? photo.fileDataRepresentation() : nil)
    }

    /// The photo drawn the right way up, whatever its orientation tag.
    static func upright(_ data: Data) -> CGImage? {
        guard let image = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}

/// The live picture, filling its frame.
private struct DipstickPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
#endif
