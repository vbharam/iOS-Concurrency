/// Copyright (c) 2019 vbharam LLC


import UIKit
import CoreImage

let dataSourceURL = URL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")!

class ListViewController: UITableViewController {
    var photos: [PhotoRecord] = []
    let pendingOperations = PendingOperations()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "Classic Photos"
    
    // Fetch Data:
    fetchPhotoDetails()
  }
    
    func fetchPhotoDetails() {
        let request = URLRequest(url: dataSourceURL)
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        // 1:
        let task = URLSession(configuration: .default).dataTask(with: request) { data, response, error in
            
            // 2
            let alertController = UIAlertController(title: "Oops!",
                                                    message: "There was an error fetching photo details.",
                                                    preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default)
            alertController.addAction(okAction)
            
            if let data = data {
                do {
                    // 3: Create a dictionary from the property list
                    if let dataSourceDict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] {
                        
                        // 4:
                        for (name, value) in dataSourceDict {
                            if let url = URL(string: value) {
                                let photoRecord = PhotoRecord(name: name, url: url)
                                self.photos.append(photoRecord)
                            }
                            
                        }
                    }
                    
                    // Show Data:
                    DispatchQueue.main.async {
                        UIApplication.shared.isNetworkActivityIndicatorVisible = false
                        self.tableView.reloadData()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.present(alertController, animated: false, completion: nil)
                    }
                }
            }
            
            if error != nil {
                DispatchQueue.main.async {
                    UIApplication.shared.isNetworkActivityIndicatorVisible = false
                    self.present(alertController, animated: false, completion: nil)
                }
            }
        }
        
        task.resume()
    }
    
    func startOperations(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
        switch photoRecord.state {
        case .new:
            startDownload(for: photoRecord, at: indexPath)
        case .downloaded:
            startFiltration(for: photoRecord, at: indexPath)
        default:
            NSLog("do nothing")
        }
    }
    
    func startDownload(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
        guard pendingOperations.downloadsInProgress[indexPath] == nil else { return }
        
        let downloader = ImageDownloader(photoRecord)
        
        // Add the completion block which will be executed when the operation is completed. This is great place to let the app know that the operation has finshed.
        // Completion block is executed even if the task is cancelled, so you must check this property.
        
        downloader.completionBlock = {
            if downloader.isCancelled { return }
            
            // You don't know which thread the completion block is called on, so you need to trigger main thread to reload the data
            DispatchQueue.main.async {
                self.pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
                self.tableView.reloadRows(at: [indexPath], with: .fade)
            }
        }
        
        pendingOperations.downloadsInProgress[indexPath] = downloader
        
        // This is how you actually get these operations to start running — the queue takes care of the scheduling for you once you’ve added the operation.
        pendingOperations.downloadQueue.addOperation(downloader)
    }
    
    func startFiltration(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
        guard pendingOperations.filtrationsInProgress[indexPath] == nil else { return }
        
        let filterer = ImageFiltration(photoRecord)
        
        filterer.completionBlock = {
            if filterer.isCancelled { return }
            
            DispatchQueue.main.async {
                self.pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
                self.tableView.reloadRows(at: [indexPath], with: .fade)
            }
        }
        
        pendingOperations.filtrationsInProgress[indexPath] = filterer
        pendingOperations.filtrationQueue.addOperation(filterer)
    }
    
    func suspendAllOperations() {
        pendingOperations.downloadQueue.isSuspended = true
        pendingOperations.filtrationQueue.isSuspended = true
    }
    
    func resumeAllOperations() {
        pendingOperations.downloadQueue.isSuspended = false
        pendingOperations.filtrationQueue.isSuspended = false
    }
    
    func loadImagesForOnscreenCells() {
        // 1: All all visible rows
        if let pathsArray = tableView.indexPathsForVisibleRows {
            
            // 2: Collect all pending operations, both download & filter
            var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
            allPendingOperations.formUnion(pendingOperations.filtrationsInProgress.keys)
            
            // 3: Set all tasks to be cancelled & subtract the visible rows from it
            var toBeCancelled = allPendingOperations
            let visiblePaths = Set(pathsArray)
            toBeCancelled.subtract(pathsArray)
            
            // 4: Set only visible rows tasks to be started & then remove  the ones where operations are already pending
            var toBeStarted = visiblePaths
            toBeStarted.subtract(allPendingOperations)
            
            // 5: Lopp through the ones that need to be cancelled & remove their reference from pending ops
            for indexPath in toBeCancelled {
                // Cancel Download task
                if let pendingOp = pendingOperations.downloadsInProgress[indexPath] {
                    pendingOp.cancel()
                }
                pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
                // Cancel Filtration task:
                if let filterOp = pendingOperations.filtrationsInProgress[indexPath] {
                    filterOp.cancel()
                }
                pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
            }
            
            // 6:
            for indexPath in toBeStarted {
                let recordToProcess = photos[indexPath.row]
                startOperations(for: recordToProcess, at: indexPath)
            }
        }
    }
    
  // MARK: - Table view data source

  override func tableView(_ tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
    return photos.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath)
    
    // 1: To provide feedback to the user, create a UIActivityIndicatorView
    if cell.accessoryView == nil {
        let indicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        cell.accessoryView = indicator
    }
    
    let indicator = cell.accessoryView as! UIActivityIndicatorView
    
    let photoDetail = photos[indexPath.row]
    
    // Configure the cell...
    cell.textLabel?.text = photoDetail.name
    cell.imageView?.image = photoDetail.image
    
    switch photoDetail.state {
    case .filtered:
        indicator.stopAnimating()
    case .failed:
        indicator.stopAnimating()
        cell.textLabel?.text = "Failed to load"
    case .new, .downloaded:
        indicator.startAnimating()
        // You tell the table view to start operations only if the table view is not scrolling.
        if !tableView.isDragging && !tableView.isDecelerating {
            startOperations(for: photoDetail, at: indexPath)
        }
    }
    
    return cell
  }
  
  // MARK: - image processing
  func applySepiaFilter(_ image:UIImage) -> UIImage? {
    let inputImage = CIImage(data:UIImagePNGRepresentation(image)!)
    let context = CIContext(options:nil)
    let filter = CIFilter(name:"CISepiaTone")
    filter?.setValue(inputImage, forKey: kCIInputImageKey)
    filter!.setValue(0.8, forKey: "inputIntensity")

    guard let outputImage = filter!.outputImage,
      let outImage = context.createCGImage(outputImage, from: outputImage.extent) else {
        return nil
    }
    return UIImage(cgImage: outImage)
  }
    
    
    // MARK: SCROLLVIEW DELEGATE:
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // As the user starts scrolling, you want to see what use wants to do. So, you will want to suspend all operations and take a look at what the user wants to see.
        suspendAllOperations()
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // If the decelerate == false, it means user stops dragging the tableview.
        // Therefore, you want to resume suspended operations, cancel off-screen operations & start on-screen operations
        if !decelerate {
            loadImagesForOnscreenCells()
            resumeAllOperations()
        }
    }
    
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Scrollview stopped decelerating
        loadImagesForOnscreenCells()
        resumeAllOperations()
    }
}
