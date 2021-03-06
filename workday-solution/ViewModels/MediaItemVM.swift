//
//  MediaItemViewModel.swift
//  workday-solution
//
//  Created by Clinton Buie on 4/6/18.
//  Copyright © 2018 AmateMint. All rights reserved.
//

import Foundation
import PromiseKit
import Cache
import NotificationBannerSwift

public typealias ProgressClosure = (Float) -> Void

class MediaItemVM {
    
    private(set) public var mediaItems:[MediaItem]
    
    init() {
        mediaItems = [MediaItem]()
    }
    
    public func getMediaItems(progressClosure:@escaping ProgressClosure) {
        let q = DispatchQueue.global(qos: .background)
        let mainQ = DispatchQueue.main
        firstly {
            APIService.sharedInstance.getAllMedia()
            }.then(on:q) { (items) -> Promise<[MediaItem]> in
                guard let mediaIds = items.media_items else {
                    return Promise { seal in
                        seal.fulfill([MediaItem]())
                    }
                }
                let cache = Cache.sharedInstance
                if try cache.checkCache(items) {
                    return Promise { seal in
                        let result = try cache.retrieveFromCache(items)
                        mainQ.async {
                            progressClosure(1.0)
                        }
                        seal.fulfill(result)
                    }
                } else {
                    return APIService.sharedInstance.downloadMediaItems(mediaIds, resultArray: [MediaItem](), progressClosure: progressClosure)
                }
            }.then { (result) -> Promise<[MediaItem]> in
                let items = MediaItems()
                let cache = Cache.sharedInstance
                try cache.saveToCache(items, mediaItemArray: result)
                return self.sanitizeResults(result)
            }.done { (result) in
                self.mediaItems = result
            }.catch { (error) in
                mainQ.async {
                    let banner = StatusBarNotificationBanner(title: error.localizedDescription, style: .info)
                    banner.show()
                }
        }
    }
    
    
    private func sanitizeResults(_ items:[MediaItem]) -> Promise<[MediaItem]> {
        return Promise { seal in
            let filterResults = self.filterDuplicateLinks(items)
            let finalResults = self.filterValidExtensions(filterResults)
            seal.fulfill(finalResults)
        }
    }
    
    private func filterDuplicateLinks(_ items:[MediaItem]) -> [MediaItem] {
        let mediaSet = NSMutableSet()
        let result = items.filter { (item) -> Bool in
            if !mediaSet.contains(item.url) {
                mediaSet.add(item.url)
                return true
            }
            return false
        }
        return result
    }
    
    private func filterValidExtensions(_ items:[MediaItem]) -> [MediaItem] {
        
        // Valid iOS Movie Extensions
        let movieExtensions = Set<String>(["mp4","mov","ts"])
        let result = items.filter { (item) -> Bool in
            guard let filePath = item.url?.components(separatedBy: "/").last else {
                return false
            }
            guard let fileExtension = filePath.components(separatedBy: ".").last?.localizedLowercase else {
                return false
            }
            return movieExtensions.contains(fileExtension)
        }
        return result
    }
}
