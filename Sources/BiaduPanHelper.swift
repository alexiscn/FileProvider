//
//  BiaduPanHelper.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/8.
//

import Foundation


public final class BaiduPanFileObject: FileObject {
    
    internal convenience init?(jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(json: json)
    }
    
    internal init?(json: [String: Any]) {
        guard let name = json["server_filename"] as? String else { return nil }
        guard let path = json["path"] as? String else { return nil }
        super.init(url: nil, name: name, path: path)
        let isdir = (json["isdir"] as? Int) == 1
        self.id = json["fs_id"] as? Int64
        self.type = isdir ? .directory: .regular
        self.size = json["size"] as? Int64 ?? -1
        self.modifiedDate = (json["server_mtime"] as? String).flatMap(Date.init(rfcString:))
        self.creationDate = (json["server_ctime"] as? String).flatMap(Date.init(rfcString:))
        self.fileHash = json["md5"] as? String
    }
    
    // The document identifier is a value assigned by the BaiduPan to a file.
    public internal(set) var id: Int64? {
        get {
            return allValues[.fileResourceIdentifierKey] as? Int64
        }
        set {
            allValues[.fileResourceIdentifierKey] = newValue
        }
    }
    
    /// The MD5 checksum for the content of the file. This is only applicable to files with binary content in Google Drive.
    public internal(set) var fileHash: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
}


/// Baidu Pan account object
public final class BaiduPanAccount {
    
    public enum Vip: Int {
        case normal = 0
        case vip
        case svip
    }
    
    public let name: String?
    
    public let diskName: String?
    
    public let avatarURLString: String?
    
    public let vipType: Vip?
    
    public let uk: Int?
    
    init(json: [String: Any]) {
     
        name = json["baidu_name"] as? String
        diskName = json["netdisk_name"] as? String
        avatarURLString = json["avatar_url"] as? String
        if let vip = json["vip_ type"] as? Int {
            vipType = Vip(rawValue: vip)
        } else {
            vipType = nil
        }
        uk = json["uk"] as? Int
    }
    
}
