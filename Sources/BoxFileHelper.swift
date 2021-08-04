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
        guard let path = json["name"] as? String else { return nil }
        super.init(url: nil, name: name, path: path)
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.id = json["id"] as? String
        self.type = (json["type"] as? String) == "folder" ? .directory: .regular
        self.modifiedDate = (json["modified_at"] as? String).flatMap(Date.init(rfcString:))
        self.creationDate = (json["created_at"] as? String).flatMap(Date.init(rfcString:))
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
}
