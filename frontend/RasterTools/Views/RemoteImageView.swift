//
//  RemoteImageView.swift
//  RasterTools
//

import SwiftUI

/// Loads an image asynchronously from a data-fetching closure.
/// Shows a progress spinner while loading and an error indicator on failure.
struct RemoteImageView: View {
    let load: () async throws -> Data

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                if let nsImage = NSImage(data: data) {
                    image = nsImage
                } else {
                    error = "Invalid image data"
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
