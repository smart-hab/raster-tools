//
//  RemoteImageView.swift
//  RasterTools
//

import SwiftUI
import ImageIO

/// Loads an image asynchronously from a data-fetching closure.
/// Shows a progress spinner while loading and an error indicator on failure.
///
/// An optional `overlay` builder draws on top of the loaded image. When present,
/// the image is rendered with `.fit` (no cropping) and the overlay receives the
/// decoded `CGImage` plus the letterboxed content rect the image occupies on
/// screen, so callers can align geographic annotations to the pixels.
///
/// The `CGImage` is decoded straight from the fetched bytes via `CGImageSource`,
/// off the main thread. This is deterministic — unlike `NSImage.cgImage(...)`,
/// whose bitmap rep realizes lazily and can transiently return nil until a
/// render pass warms it, which produced intermittently-blank overlays.
struct RemoteImageView<Overlay: View>: View {
    let load: () async throws -> Data
    let overlay: ((CGImage, CGRect) -> Overlay)?

    @State private var image: CGImage?
    @State private var isLoading = true
    @State private var error: String?

    init(
        load: @escaping () async throws -> Data,
        @ViewBuilder overlay: @escaping (CGImage, CGRect) -> Overlay
    ) {
        self.load = load
        self.overlay = overlay
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))

            if let image {
                imageContent(image)
            } else if isLoading {
                ProgressView()
            } else if let error {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
            }
        }
        .task {
            do {
                let data = try await load()
                if let decoded = await Self.decode(data) {
                    image = decoded
                } else {
                    print("[RemoteImageView] thumbnail decode failed (\(data.count) bytes)")
                    error = "Invalid image data"
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func imageContent(_ image: CGImage) -> some View {
        let imageSize = CGSize(width: image.width, height: image.height)
        if let overlay {
            GeometryReader { geo in
                let rect = Self.fittedRect(imageSize: imageSize, in: geo.size)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                overlay(image, rect)
            }
        } else {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Decodes a `CGImage` from encoded bytes off the main thread. Deterministic:
    /// returns a fully-realized image or nil (a genuine decode failure).
    private static func decode(_ data: Data) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
    }

    /// The rectangle an aspect-fit image of `imageSize` occupies within `bounds`,
    /// centered (letterboxed on the shorter axis).
    static func fittedRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

extension RemoteImageView where Overlay == EmptyView {
    init(load: @escaping () async throws -> Data) {
        self.load = load
        self.overlay = nil
    }
}
