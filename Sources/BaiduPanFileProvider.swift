//
//  BaiduPanFileProvider.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/8.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

/**
 Allows accessing to Baidu Pan stored files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 */
open class BaiduPanFileProvider: HTTPFileProvider, FileProviderSharing {
    
    override open class var type: String { return "BaiduPan" }
    
    /// BaiduPan rest API URL, which is equal with [https://pan.baidu.com/rest/2.0](https://pan.baidu.com/rest/2.0)
    public let apiURL: URL
    
    public init(credential: URLCredential?, cache: URLCache? = nil) {
        self.apiURL = URL(string: "https://pan.baidu.com/rest/2.0")!
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
    
    open override func contentsOfDirectory(path: String, completionHandler: @escaping ([FileObject], Error?) -> Void) {
        
        var parameters: [String: String] = [:]
        parameters["method"] = "list"
        parameters["dir"] = path
        parameters["access_token"] = credential?.password ?? ""
        
        let query = String(format: "/xpan/file?%@", parameters.fpQuery)
        let urlString = self.apiURL.absoluteString.appending(query)
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request, completionHandler: { [weak self] (data, response, error) in
            guard let `self` = self else {
                completionHandler([], error)
                return
            }
            
            guard let json = data?.deserializeJSON(), let entries = json["list"] as? [Any] else {
                let err = URLError(.badServerResponse, url: self.url(of: path))
                return completionHandler([], err)
            }
            
            var files = [FileObject]()
            for entry in entries {
                if let entry = entry as? [String: Any], let file = BaiduPanFileObject(json: entry) {
                    files.append(file)
                }
            }
            completionHandler(files, error)
        })
        task.resume()
    }
    
    public func publicLink(to path: String, completionHandler: @escaping (URL?, FileObject?, Date?, Error?) -> Void) {
        
        var parameters: [String: String] = [:]
        parameters["access_token"] = credential?.password ?? ""
        parameters["fsids"] = "[\(path)]"
        parameters["dlink"] = "1"
        parameters["method"] = "filemetas"
        
        let urlString = apiURL.absoluteString.appending("/xpan/multimedia?\(parameters.fpQuery)")
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON(), let entry = (json["list"] as? [Any])?.first else {
                completionHandler(nil, nil, nil, error)
                return
            }
            let objectJson = (entry as? [String: Any]) ?? [:]
            let dlink = (objectJson["dlink"] as? String) ?? ""
            let url = URL(string: dlink)
            let object = BaiduPanFileObject(json: json)
            completionHandler(url, object, nil, error)
        })
        task.resume()
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        
        var requestDictionary = [String: Any]()
        requestDictionary["async"] = 1
        
        struct Move: CustomStringConvertible {
            let path: String
            let dest: String
            let newname: String
            
            var description: String {
                return "{\"path\":\"\(path)\",\"dest\":\"\(dest)\",\"newname\":\"\(newname)\"}"
            }
        }
        
        let action: String
        let method: String
        switch operation {
        case .fetch(path: let path):
            return URLRequest(url: URL(string: "")!)
        case .move(let source, let dest):
            action = "move"
            method = "POST"
            let destPath = dest.components(separatedBy: "/").dropLast().joined(separator: "/")
            let newname = dest.components(separatedBy: "/").last ?? ""
            let move = Move(path: source, dest: destPath, newname: newname)
            requestDictionary["filelist"] = [move]
        case .remove(let path):
            action = "delete"
            method = "POST"
            requestDictionary["filelist"] = [path]
            requestDictionary["ondup"] = "fail"
        default:
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        let accessToken = credential?.password ?? ""
        let urlString = apiURL.absoluteString.appending("/xpan/file?method=filemanager&access_token=\(accessToken)&opera=\(action)")
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        
        // different from other service
        let body = requestDictionary.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        
        return request
    }
    
    public func getCurrentUser(completionHandler: @escaping (BaiduPanAccount?, Error?) -> Void) {
        
        var parameters: [String: String] = [:]
        parameters["method"] = "uinfo"
        parameters["access_token"] = credential?.password ?? ""
        
        let urlString = apiURL.absoluteString.appending("/xpan/nas?\(parameters.fpQuery)")
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil, error)
                return
            }
            let object = BaiduPanAccount(json: json)
            completionHandler(object, error)
        })
        task.resume()
    }
}
