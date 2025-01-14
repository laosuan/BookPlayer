//
//  RemoteItemListView.swift
//  BookPlayerWatch
//
//  Created by Gianni Carlo on 18/11/24.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import BookPlayerWatchKit
import SwiftUI
import TipKit

struct RemoteItemListView: View {
  @Environment(\.scenePhase) var scenePhase
  @ObservedObject var coreServices: CoreServices
  @ObservedObject var playerManager: PlayerManager
  @State var items: [SimpleLibraryItem]
  @State var playingItemParentPath: String?
  @State private var isLoading = false
  @State private var error: Error?
  @State var showPlayer = false
  @State var isRefreshing: Bool = false
  @State var isFirstLoad = true

  let folderRelativePath: String?

  init(
    coreServices: CoreServices,
    folderRelativePath: String? = nil
  ) {
    self.coreServices = coreServices
    self.playerManager = coreServices.playerManager
    let fetchedItems =
      coreServices.libraryService.fetchContents(
        at: folderRelativePath,
        limit: nil,
        offset: nil
      ) ?? []
    self._items = .init(initialValue: fetchedItems)
    let lastItem = coreServices.libraryService.getLastPlayedItems(limit: 1)?.first
    self.folderRelativePath = folderRelativePath

    if let lastItem {
      self._playingItemParentPath = .init(
        initialValue: getPathForParentOfItem(currentPlayingPath: lastItem.relativePath)
      )
    } else {
      self._playingItemParentPath = .init(initialValue: nil)
    }
  }

  private func syncListContents(ignoreLastTimestamp: Bool) async {
    guard
      await coreServices.syncService.canSyncListContents(
        at: folderRelativePath,
        ignoreLastTimestamp: ignoreLastTimestamp
      )
    else { return }

    do {
      try await coreServices.syncService.syncListContents(at: folderRelativePath)
    } catch BPSyncError.reloadLastBook(let relativePath) {
      reloadLastBook(relativePath: relativePath)
    } catch BPSyncError.differentLastBook(let relativePath) {
      await setSyncedLastPlayedItem(relativePath: relativePath)
    } catch {
      self.error = error
    }

    items =
      coreServices.libraryService.fetchContents(
        at: folderRelativePath,
        limit: nil,
        offset: nil
      ) ?? []

    if let lastPlayedItem {
      playingItemParentPath = getPathForParentOfItem(currentPlayingPath: lastPlayedItem.relativePath)
    } else {
      playingItemParentPath = nil
    }
  }

  @MainActor
  private func reloadLastBook(relativePath: String) {
    let wasPlaying = playerManager.isPlaying
    playerManager.stop()

    Task { @MainActor in
      do {
        try await coreServices.playerLoaderService.loadPlayer(
          relativePath,
          autoplay: wasPlaying
        )
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func setSyncedLastPlayedItem(relativePath: String) async {
    /// Only continue overriding local book if it's not currently playing
    guard playerManager.isPlaying == false else { return }

    await coreServices.syncService.setLibraryLastBook(with: relativePath)

    do {
      try await coreServices.playerLoaderService.loadPlayer(
        relativePath,
        autoplay: false
      )
    } catch {
      self.error = error
    }
  }

  func getForegroundColor(for item: SimpleLibraryItem) -> Color {
    guard let lastPlayedItem else { return .primary }

    if item.relativePath == lastPlayedItem.relativePath {
      return .accentColor
    }

    return item.relativePath == playingItemParentPath ? .accentColor : .primary
  }

  func getPathForParentOfItem(currentPlayingPath: String) -> String? {
    let parentFolders: [String] = currentPlayingPath.allRanges(of: "/")
      .map { String(currentPlayingPath.prefix(upTo: $0.lowerBound)) }
      .reversed()

    guard let folderRelativePath = self.folderRelativePath else {
      return parentFolders.last
    }

    guard let index = parentFolders.firstIndex(of: folderRelativePath) else {
      return nil
    }

    let elementIndex = index - 1

    guard elementIndex >= 0 else {
      return nil
    }

    return parentFolders[elementIndex]
  }

  var lastPlayedItem: SimpleLibraryItem? {
    guard
      let currentItem = playerManager.currentItem,
      let lastPlayedItem = coreServices.libraryService.getSimpleItem(with: currentItem.relativePath)
    else {
      return coreServices.libraryService.getLastPlayedItems(limit: 1)?.first
    }

    return lastPlayedItem
  }

  var body: some View {
    RefreshableListView(refreshing: $isRefreshing) {
      if folderRelativePath == nil {
        Section {
          if let lastPlayedItem {
            RemoteItemListCellView(model: .init(item: lastPlayedItem, coreServices: coreServices)) {
              Task {
                do {
                  isLoading = true
                  try await coreServices.playerLoaderService.loadPlayer(lastPlayedItem.relativePath, autoplay: true)
                  showPlayer = true
                  isLoading = false
                } catch {
                  isLoading = false
                  self.error = error
                }
              }
            }
            .applyPrimaryHandGesture()
          }
        } header: {
          Text(verbatim: "watchapp_last_played_title".localized)
            .foregroundStyle(Color.accentColor)
        }
      }

      Section {
        if #available(watchOS 10.0, *),
          folderRelativePath == nil,
           !items.isEmpty
        {
          TipView(SwipeInlineTip())
            .listRowBackground(Color.clear)
        }

        ForEach(items) { item in
          if item.type == .folder {
            NavigationLink {
              RemoteItemListView(
                coreServices: coreServices,
                folderRelativePath: item.relativePath
              )
            } label: {
              RemoteItemListCellView(model: .init(item: item, coreServices: coreServices)) {}
                .allowsHitTesting(false)
                .foregroundColor(getForegroundColor(for: item))
            }
          } else {
            RemoteItemListCellView(model: .init(item: item, coreServices: coreServices)) {
              Task {
                do {
                  isLoading = true
                  try await coreServices.playerLoaderService.loadPlayer(item.relativePath, autoplay: true)
                  showPlayer = true
                  isLoading = false
                } catch {
                  isLoading = false
                  self.error = error
                }
              }
            }
          }
        }
      } header: {
        Text(verbatim: folderRelativePath?.components(separatedBy: "/").last ?? "library_title".localized)
          .foregroundStyle(Color.accentColor)
          .padding(.top, folderRelativePath == nil ? 10 : 0)
      }

      /// Create padding at the bottom
      Section {
        Spacer().frame(height: 10)
          .listRowBackground(Color.clear)
      } header: {
        Text("")
      }
      .accessibilityHidden(true)
    }
    .ignoresSafeArea(edges: [.bottom])
    .background(
      NavigationLink(destination: RemotePlayerView(playerManager: coreServices.playerManager), isActive: $showPlayer) {
        EmptyView()
      }
      .opacity(0)
    )
    .errorAlert(error: $error)
    .overlay {
      Group {
        if isLoading {
          ProgressView()
            .tint(.white)
            .padding()
            .background(
              Color.black
                .opacity(0.9)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .ignoresSafeArea(.all)
        }
      }
    }
    .onChange(of: isRefreshing) { newValue in
      guard newValue else { return }

      Task {
        // Delay the task by 1 second to avoid jumping animations
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await syncListContents(ignoreLastTimestamp: true)
        isRefreshing = false
      }
    }
    .onChange(of: scenePhase) { newPhase in
      guard
        newPhase == .active,
        coreServices.playerManager.isPlaying
      else { return }

      showPlayer = true
    }
    .onAppear {
      guard isFirstLoad else { return }
      isFirstLoad = false

      Task {
        await syncListContents(ignoreLastTimestamp: false)
      }
    }
  }
}
