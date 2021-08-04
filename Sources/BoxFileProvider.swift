//
//  BoxFileProvider.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/2.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

open class BoxFileProvider: HTTPFileProvider, FileProviderSharing {
    
    override open class var type: String { return "Box" }
    
    /// Box API URL, which is equal with [https://api.box.com/2.0](https://api.box.com/2.0)
    public let apiURL: URL
    
    /// Box contents upload API URL, which is equal with [https://upload.box.com/api/2.0](https://upload.box.com/api/2.0)
    public let uploadURL: URL!
    
    /**
     Initializer for Box provider with given client ID and Token.
     These parameters must be retrieved via [OAuth2 API of Box](https://developer.box.com/guides/authentication/oauth2/).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. The latter is easier to use and prefered.
     
     - Parameter credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
     - Parameter cache: A URLCache to cache downloaded files and contents.
    */
    public init(credential: URLCredential?, cache: URLCache? = nil) {
        self.apiURL = URL(string: "https://api.box.com/2.0")!
        self.uploadURL = URL(string: "https://upload.box.com/api/2.0")!
        super.init(baseURL: nil, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        self.init(credential: aDecoder.decodeObject(of: URLCredential.self, forKey: "credential"))
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = BoxFileProvider(credential: self.credential, cache: self.cache)
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
        _ = paginated("folders/\(path)/items/", requestHandler: { [weak self] token -> URLRequest? in
            guard let `self` = self else { return nil }
            
            var components = URLComponents(string: self.apiURL.appendingPathComponent("folders/\(path)/items").absoluteString)!
            if let token = token {
                components.queryItems = [
                    URLQueryItem(name: "offset", value: token),
                    URLQueryItem(name: "fields", value: "id,type,name,size,created_at,modified_at")
                ]
            } else {
                components.queryItems = [
                    URLQueryItem(name: "fields", value: "id,type,name,size,created_at,modified_at")
                ]
            }
            
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue(authentication: self.credential, with: .oAuth2)
            return request
        }, pageHandler: { [weak self] (data, _) -> (files: [FileObject], error: Error?, newToken: String?) in
            guard let `self` = self else { return ([], nil, nil) }
            
            guard let json = data?.deserializeJSON(), let entries = json["entries"] as? [Any] else {
                let err = URLError(.badServerResponse, url: self.apiURL.appendingPathComponent("folders/\(path)/items"))
                return ([], err, nil)
            }
            
            var files = [FileObject]()
            for entry in entries {
                if let json = entry as? [String: Any], let file = BoxFileObject(json: json) {
                    files.append(file)
                }
            }
            let offset = (json["offset"] as? NSNumber)?.int64Value ?? 0
            let token = offset == 0 ? nil: String(offset)
            return (files, nil, token)
        }, completionHandler: completionHandler)
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping (FileObject?, Error?) -> Void) {
        // not implement yet
    }
    
    public func publicLink(to path: String, completionHandler: @escaping (URL?, FileObject?, Date?, Error?) -> Void) {
        // not implement yet
    }
    
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    open override func storageProperties(completionHandler: @escaping (VolumeObject?) -> Void) {
        let url = URL(string: "users/me", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            volume.totalCapacity = (json["space_amount"] as? NSNumber)?.int64Value ?? -1
            volume.usage = (json["space_used"] as? NSNumber)?.int64Value ?? 0
            completionHandler(volume)
        })
        task.resume()
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        let errorDesc: String?
        if let response = data?.deserializeJSON() {
            errorDesc = response["message"] as? String
        } else {
            errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
        }
        return FileProviderBoxError(code: code, path: path ?? "", serverDescription: errorDesc)
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        
        func uploadRequest(to path: String) -> URLRequest {
            var requestDictionary = [String: Any]()
            let url: URL = URL(string: "files/content", relativeTo: uploadURL)!
            requestDictionary["path"] = path
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(authentication: credential, with: .oAuth2)
            request.setValue(contentType: .stream)
            return request
        }
        
        func downloadRequest(from path: String) -> URLRequest {
            
            var url = URL(string: "")!
            return URLRequest(url: url)
        }
        
        /// https://developer.box.com/reference/put-files-id/
        func moveRequest(from source: String, to dest: String) -> URLRequest {
            let url = URL(string: "files/\(source)", relativeTo: apiURL)!
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            return request
        }
        
        switch operation {
        case .move(let source, let dest):
            return moveRequest(from: source, to: dest)
        default:
            return URLRequest(url: URL(string: "")!)
        }
    }
    
    
}
