/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit

struct PhotoManagerNotification {
  // Notification when new photo instances are added
  static let contentAdded = Notification.Name("com.raywenderlich.GooglyPuff.PhotoManagerContentAdded")
  // Notification when content updates (i.e. Download finishes)
  static let contentUpdated = Notification.Name("com.raywenderlich.GooglyPuff.PhotoManagerContentUpdated")
}

struct PhotoURLString {
  // Photo Credit: Devin Begley, http://www.devinbegley.com/
  static let overlyAttachedGirlfriend = "https://i.imgur.com/UvqEgCv.png"
  static let successKid = "https://i.imgur.com/dZ5wRtb.png"
  static let lotsOfFaces = "https://i.imgur.com/tPzTg7A.jpg"
}

typealias PhotoProcessingProgressClosure = (_ completionPercentage: CGFloat) -> Void
typealias BatchPhotoDownloadingCompletionClosure = (_ error: NSError?) -> Void

final class PhotoManager {
  private init() {}
  static let shared = PhotoManager()
  
  private let concurrentQueue = DispatchQueue(label: "net.codecoop.GooglyPuff.photoQueue", attributes: .concurrent)
  private var unsafePhotos: [Photo] = []
  
  var photos: [Photo] {
    var photosCopy: [Photo]!
    
    // 1: dispatch Sync onto the concurrentQueue to perform the read.
    concurrentQueue.sync {
        photosCopy = self.unsafePhotos
    }
    return photosCopy
  }
  
  func addPhoto(_ photo: Photo) {
    
    // 1: Dispatch the write operation async with the barrier task. When it executes, it will be the only task in the queue
    concurrentQueue.async(flags: .barrier) { [weak self] in
        guard let strongSelf = self else { return }
        
        // 2: Add our object
        strongSelf.unsafePhotos.append(photo)
        
        // 3: Let the UI know of this change
        DispatchQueue.main.async { [weak self] in
            self?.postContentAddedNotification()
        }
    }
  }
  
  func downloadPhotos(withCompletion completion: BatchPhotoDownloadingCompletionClosure?) {

    // 1: Here we don't need to surround the method with async, b/c yo are not blocking the main thread
    var storedError: NSError?
    let downloadGroup = DispatchGroup()
    for address in [PhotoURLString.overlyAttachedGirlfriend,
                    PhotoURLString.successKid,
                    PhotoURLString.lotsOfFaces] {
                        let url = URL(string: address)
                        downloadGroup.enter()
                        let photo = DownloadPhoto(url: url!) { _, error in
                            if error != nil {
                                storedError = error
                            }
                            downloadGroup.leave()
                        }
                        PhotoManager.shared.addPhoto(photo)
    }
    
    // 2: .notify(queue: ) - serves as the asynchronous completion closure
    downloadGroup.notify(queue: DispatchQueue.main) {
        completion?(storedError)
    }
  }
    
    
  func downloadPhotos2(withCompletion completion: BatchPhotoDownloadingCompletionClosure?) {
    var storedError: NSError?
    let downloadGroup = DispatchGroup()
    var addresses = [PhotoURLString.overlyAttachedGirlfriend,
                     PhotoURLString.successKid,
                     PhotoURLString.lotsOfFaces]
    
    addresses += addresses + addresses
    var blocks: [DispatchWorkItem] = []
    
    for index in 0..<addresses.count {
        downloadGroup.enter()
        let block = DispatchWorkItem(flags: .inheritQoS) {
            let address = addresses[index]
            let url = URL(string: address)
            
            let photo = DownloadPhoto(url: url!, completion: { (_, error) in
                if error != nil {
                    storedError = error
                }
                downloadGroup.leave()
            })
            PhotoManager.shared.addPhoto(photo)
        }
        blocks.append(block)
        
        DispatchQueue.main.async(execute: block)
    }
    
    // Cancel:
    var flag = false
    for block in blocks[3..<blocks.count] {
        if flag {
            block.cancel()
            downloadGroup.leave()
        }
        flag = !flag
    }
    
    downloadGroup.notify(queue: DispatchQueue.main) {
        completion?(storedError)
    }
  }
  
  private func postContentAddedNotification() {
    NotificationCenter.default.post(name: PhotoManagerNotification.contentAdded, object: nil)
  }
}
