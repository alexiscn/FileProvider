//
//  BoxFileHelper.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/4.
//

import Foundation

/// Error returned by Box server when trying to access or do operations on a file or folder.
public struct FileProviderBoxError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let serverDescription: String?
}

/// Containts path, url and attributes of a Box file or resource.
public final class BoxFileObject: FileObject {
    
    internal convenience init?(jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(json: json)
    }
    
    internal init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        guard let id = json["id"] as? String else { return nil }
        super.init(url: nil, name: name, path: id)
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.id = id
        self.type = (json["type"] as? String) == "folder" ? .directory: .regular
        self.modifiedDate = (json["modified_at"] as? String).flatMap(Date.init(rfcString:))
        self.creationDate = (json["created_at"] as? String).flatMap(Date.init(rfcString:))
        self.entryTag = json["etag"] as? String
        self.fileHash = json["sha1"] as? String
    }
    
    /// The document identifier is a value assigned by the Box to a file.
    /// This value is used to identify the document regardless of where it is moved on a volume.
    public internal(set) var id: String? {
        get {
            return allValues[.fileResourceIdentifierKey] as? String
        }
        set {
            allValues[.fileResourceIdentifierKey] = newValue
        }
    }
    
    /// HTTP E-Tag, can be used to mark changed files.
    public internal(set) var entryTag: String? {
        get {
            return allValues[.entryTagKey] as? String
        }
        set {
            allValues[.entryTagKey] = newValue
        }
    }
    
    public internal(set) var fileHash: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
}

extension BoxFileProvider {
    
    func upload_multipart_data(_ targetPath: String, data: Data, operation: FileOperationType,
                                        overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.upload_multipart(targetPath, operation: operation, size: Int64(data.count), overwrite: overwrite, dataProvider: {
            let range = $0.clamped(to: 0..<Int64(data.count))
            return data[range]
        }, completionHandler: completionHandler)
    }
    
    func upload_multipart_file(_ targetPath: String, file: URL, operation: FileOperationType,
                                        overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        // upload task can't handle uploading file
        
        return self.upload_multipart(targetPath, operation: operation, size: file.fileSize, overwrite: overwrite, dataProvider: { range in
            guard let handle = FileHandle(forReadingAtPath: file.path) else {
                throw CocoaError(.fileNoSuchFile, path: targetPath)
            }
            
            defer {
                handle.closeFile()
            }
            
            let offset = range.lowerBound
            handle.seek(toFileOffset: UInt64(offset))
            guard Int64(handle.offsetInFile) == offset else {
                throw CocoaError(.fileReadTooLarge, path: targetPath)
            }
            
            return handle.readData(ofLength: range.count)
        }, completionHandler: completionHandler)
    }
    
    private func upload_multipart(_ targetPath: String, operation: FileOperationType, size: Int64, overwrite: Bool,
                                  dataProvider: @escaping (Range<Int64>) throws -> Data, completionHandler: SimpleCompletionHandler) -> Progress? {
        guard size > 0 else { return nil }
        
        let progress = Progress(totalUnitCount: size)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let createURL = uploadURL.appendingPathComponent("files/upload_sessions")
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue(authentication: self.credential, with: .oAuth2)
        createRequest.setValue(contentType: .json)
        
        var requestDictionary = [String: Any]()
        requestDictionary["file_size"] = size
        let components = targetPath.split(separator: "/").map { String($0) }
        if components.count == 2 {
            requestDictionary["file_name"] = components[1]
            requestDictionary["folder_id"] = components[0]
        }
        createRequest.httpBody = Data(jsonDictionary: requestDictionary)
        
        let createSessionTask = session.dataTask(with: createRequest) { (data, response, error) in
            if let error = error {
                completionHandler?(error)
                return
            }
            
            if let data = data, let json = data.deserializeJSON(),
                let sessionId = json["id"] as? String,
                let partSize = json["part_size"] as? Int64 {
                let url = self.uploadURL.appendingPathComponent("files/upload_sessions/\(sessionId)")
                self.upload_multipart(url: url, operation: operation, size: size, partSize: partSize, progress: progress, dataProvider: dataProvider, completionHandler: completionHandler)
            }
        }
        createSessionTask.resume()
        
        return progress
    }
    
    private func upload_multipart(url: URL, operation: FileOperationType, size: Int64, partSize: Int64, range: Range<Int64>? = nil, uploadedSoFar: Int64 = 0,
                                  progress: Progress, dataProvider: @escaping (Range<Int64>) throws -> Data, completionHandler: SimpleCompletionHandler) {
        guard !progress.isCancelled else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authentication: self.credential, with: .oAuth2)
        
        let finalRange: Range<Int64>
        if let range = range {
            if range.count > partSize {
                finalRange = range.lowerBound..<(range.upperBound + partSize)
            } else {
                finalRange = range
            }
        } else {
            finalRange = 0..<min(partSize, size)
        }
        request.setValue(contentRange: finalRange, totalBytes: size)
        
        let data: Data
        do {
            data = try dataProvider(finalRange)
        } catch {
            dispatch_queue.async {
                completionHandler?(error)
            }
            self.delegateNotify(operation, error: error)
            return
        }
        let task = session.uploadTask(with: request, from: data)
        
        var dictionary: [String: Any] = ["type": operation.description]
        dictionary["source"] = operation.source
        dictionary["dest"] = operation.destination
        dictionary["uploadedBytes"] = NSNumber(value: uploadedSoFar)
        dictionary["totalBytes"] = NSNumber(value: size)
        task.taskDescription = String(jsonDictionary: dictionary)
        sessionDelegate?.observerProgress(of: task, using: progress, kind: .upload)
        progress.cancellationHandler = { [weak task, weak self] in
            task?.cancel()
            var deleteRequest = URLRequest(url: url)
            deleteRequest.httpMethod = "DELETE"
            self?.session.dataTask(with: deleteRequest).resume()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        
        var allData = Data()
        dataCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { data in
            allData.append(data)
        }
        // We retain self here intentionally to allow resuming upload, This behavior may change anytime!
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { [weak task] error in
            if let error = error {
                progress.cancel()
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
            
            guard let json = allData.deserializeJSON() else {
                let error = URLError(.badServerResponse, userInfo: [NSURLErrorKey: url, NSURLErrorFailingURLErrorKey: url, NSURLErrorFailingURLStringErrorKey: url.absoluteString])
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
// TODO
//            if let _ = json["error"] {
//                let code = ((task?.response as? HTTPURLResponse)?.statusCode).flatMap(FileProviderHTTPErrorCode.init(rawValue:)) ?? .badRequest
//                let error = self.serverError(with: code, path: self.relativePathOf(url: url), data: allData)
//                completionHandler?(error)
//                self.delegateNotify(operation, error: error)
//                return
//            }
//
//            if let ranges = json["nextExpectedRanges"] as? [String], let firstRange = ranges.first {
//                let uploaded = uploadedSoFar + Int64(finalRange.count)
//                let comp = firstRange.components(separatedBy: "-")
//                let lower = comp.first.flatMap(Int64.init) ?? uploaded
//                let upper = comp.dropFirst().first.flatMap(Int64.init) ?? Int64.max
//                let range = Range<Int64>(uncheckedBounds: (lower: lower, upper: upper))
//                self.upload_multipart(url: url, operation: operation, size: size, partSize: partSize, range: range, uploadedSoFar: uploaded, progress: progress,
//                                      dataProvider: dataProvider, completionHandler: completionHandler)
//                return
//            }
//
//            if let _ = json["id"] as? String {
//                completionHandler?(nil)
//                self.delegateNotify(operation)
//            }
        }
        
        task.resume()
    }
}
