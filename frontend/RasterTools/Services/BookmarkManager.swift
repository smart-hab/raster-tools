//
//  BookmarkManager.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import AppKit

/// Manages security-scoped bookmarks so the app can re-access user-selected
/// directories after relaunch (required when App Sandbox is enabled).
class BookmarkManager {
    static let shared = BookmarkManager()

    private let defaultsKey = "securityScopedBookmarks"

    private init() {}

    // MARK: - Save

    /// Creates and persists a security-scoped bookmark for the given URL.
    func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = storedBookmarks()
            bookmarks[url.path] = data
            UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
        } catch {
            print("BookmarkManager: failed to create bookmark for \(url.path): \(error)")
        }
    }

    // MARK: - Restore

    /// Resolves all saved bookmarks and starts accessing each one.
    /// Call this once at app startup.
    func restoreAllBookmarks() {
        var bookmarks = storedBookmarks()
        var updated = false

        for (path, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    if let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        bookmarks[path] = refreshed
                        updated = true
                    }
                }
                _ = url.startAccessingSecurityScopedResource()
            } catch {
                print("BookmarkManager: failed to resolve bookmark for \(path): \(error)")
                bookmarks.removeValue(forKey: path)
                updated = true
            }
        }

        if updated {
            UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
        }
    }

    func hasBookmark(for url: URL) -> Bool {
        storedBookmarks()[url.path] != nil
    }

    // MARK: - Private

    private func storedBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }
}
