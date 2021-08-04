//
//  GoogleDriveFileProvider.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/2.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

open class GoogleDriveFileProvider: HTTPFileProvider, FileProviderSharing {
    
    override open class var type: String { return "GoogleDrive" }
    
    /// Google Drive API URL, which is equal with [https://www.googleapis.com/drive/v3](https://www.googleapis.com/drive/v3)
    public let apiURL: URL
    
    /**
     Initializer for Google Drive provider with given client ID and Token.
     These parameters must be retrieved via [Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. The latter is easier to use and prefered.
     
     - Parameter credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
     - Parameter cache: A URLCache to cache downloaded files and contents.
    */
    public init(credential: URLCredential?, cache: URLCache? = nil) {
        self.apiURL = URL(string: "https://www.googleapis.com/drive/v3")!
        super.init(baseURL: nil, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        self.init(credential: aDecoder.decodeObject(of: URLCredential.self, forKey: "credential"))
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = GoogleDriveFileProvider(credential: self.credential, cache: self.cache)
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameters:
       - path: path to target directory. If empty, root will be iterated.
       - completionHandler: a closure with result of directory entries or error.
       - contents: An array of `FileObject` identifying the the directory entries.
       - error: Error returned by system.
     */
    open override func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        _ = paginated(path, requestHandler: { [weak self] token -> URLRequest? in
            guard let `self` = self else { return nil }
            
            var parameters: [String: String] = [:]
            parameters["q"] = String(format: "'%@' in parents", path)
            parameters["fields"] = "files(id,kind,name,size,createdTime,modifiedTime,mimeType)"
            if let token = token {
                parameters["pageToken"] = token
            }
            let urlString = self.apiURL.absoluteString.appending("/files?\(parameters.fpQuery)")
            var request = URLRequest(url: URL(string: urlString)!)
            request.httpMethod = "GET"
            request.setValue(authentication: self.credential, with: .oAuth2)
            return request
            
        }, pageHandler: { [weak self] (data, _) -> (files: [FileObject], error: Error?, newToken: String?) in
            guard let `self` = self else { return ([], nil, nil) }
            
            guard let json = data?.deserializeJSON(), let entries = json["files"] as? [Any] else {
                let err = URLError(.badServerResponse, url: self.url(of: path))
                return ([], err, nil)
            }
            
            var files = [FileObject]()
            for entry in entries {
                if let entry = entry as? [String: Any], let file = GoogleDriveFileObject(json: entry) {
                    files.append(file)
                }
            }
            
            return (files, nil, json["pageToken"] as? String)
            
        }, completionHandler: completionHandler)
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping (FileObject?, Error?) -> Void) {
        
    }
    
    public func publicLink(to path: String, completionHandler: @escaping (URL?, FileObject?, Date?, Error?) -> Void) {
        
    }
        
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    open override func storageProperties(completionHandler: @escaping (VolumeObject?) -> Void) {
        let url = URL(string: "about", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authentication: self.credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            let quota = json["storageQuota"] as? [String: Any]
            volume.totalCapacity = Int64(quota?["limit"] as? String ?? "-1") ?? -1
            volume.availableCapacity = Int64(quota?["usage"] as? String ?? "-1") ?? -1
            completionHandler(volume)
        })
        task.resume()
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        
        func downloadRequest(from path: String) -> URLRequest {
            let url = URL(string: "files/\(path)?alt=media", relativeTo: apiURL)!
            var request = URLRequest(url: url)
            request = URLRequest(url: url)
            request.setValue(authentication: credential, with: .oAuth2)
            return request
        }
        
        switch operation {
        case .fetch(let path):
            return downloadRequest(from: path)
        default:
        return self.apiRequest(for: operation, overwrite: overwrite)
        }
        
    }
    
    func apiRequest(for operation: FileOperationType, overwrite: Bool = false) -> URLRequest {
        
        let url: String
        let sourcePath = operation.source
        let destPath = operation.destination
        var httpMethod = "POST"
        var requestDictionary = [String: Any]()
        switch operation {
        case .create:
            url = "files"
            
            var path = sourcePath
            if sourcePath.hasSuffix("/") {
                path = String(sourcePath.dropLast())
            }
            let components = path.components(separatedBy: "/")
            let name = components.last ?? ""
            let parents = components.dropLast().joined(separator: "/")
            
            requestDictionary["name"] = name
            requestDictionary["mimeType"] = ContentMIMEType.googleFolder.rawValue
            requestDictionary["parents"] = [parents]
        case .copy:
            url = "files/\(sourcePath)/copy"
        case .move:
            url = ""
        case .remove:
            url = "files/\(sourcePath)"
            httpMethod = "DELETE"
        default:
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        
        var request = URLRequest(url: apiURL.appendingPathComponent(url))
        request.httpMethod = httpMethod
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        request.httpBody = Data(jsonDictionary: requestDictionary)
        return request
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        let errorDesc: String?
        if let response = data?.deserializeJSON() {
            errorDesc = (response["error"] as? [String: Any])?["message"] as? String
        } else {
            errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
        }
        return FileProviderGoogleDriveError(code: code, path: path ?? "", serverDescription: errorDesc)
    }
}
