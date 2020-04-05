//
//  ActionParserService.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 4/5/20.
//  Copyright © 2020 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Foundation

class ActionParserService {
    public class func process(_ url: URL) {
        guard let action = CommandParser.parse(url) else { return }

        self.handleAction(action)
    }

    public class func handleAction(_ action: Action) {
        switch action.command {
        case .play:
            self.handlePlayAction(action)
        case .download:
            self.handleDownloadAction(action)
        case .sleep:
            self.handleSleepAction(action)
        case .refresh:
            WatchConnectivityService.sharedManager.sendApplicationContext()
        case .skipRewind:
            PlayerManager.shared.rewind()
        case .skipForward:
            PlayerManager.shared.forward()
        }
    }

    private class func handleSleepAction(_ action: Action) {
        guard let value = action.getQueryValue(for: "seconds"),
            let seconds = Double(value) else {
            return
        }

        if seconds == -1 {
            SleepTimer.shared.cancel()
        } else {
            SleepTimer.shared.sleep(in: seconds)
        }
    }

    private class func handlePlayAction(_ action: Action) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        if let value = action.getQueryValue(for: "showPlayer"),
            let showPlayer = Bool(value),
            showPlayer {
            appDelegate.showPlayer()
        }

        guard let bookIdentifier = action.getQueryValue(for: "identifier") else {
            appDelegate.playLastBook()
            return
        }

        if let loadedBook = PlayerManager.shared.currentBook, loadedBook.identifier == bookIdentifier {
            PlayerManager.shared.play()
            return
        }

        let library = DataManager.getLibrary()

        guard let book = DataManager.getBook(with: bookIdentifier, from: library) else { return }

        guard let libraryVC = appDelegate.getLibraryVC() else {
            return
        }

        libraryVC.setupPlayer(book: book)
        NotificationCenter.default.post(name: .bookChange,
                                        object: nil,
                                        userInfo: ["book": book])
    }

    private class func handleDownloadAction(_ action: Action) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            let libraryVC = appDelegate.getLibraryVC() else {
            return
        }

        libraryVC.navigationController?.dismiss(animated: true, completion: nil)

        if let url = action.getQueryValue(for: "url")?.replacingOccurrences(of: "\"", with: "") {
            libraryVC.downloadBook(from: url)
        }
    }
}
