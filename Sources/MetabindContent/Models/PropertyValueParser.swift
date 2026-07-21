//
// PropertyValueParser.swift
//
// © 2025 Yap Studios LLC
//

import Foundation

enum PropertyValueError: Error {
    case unsupportedType
    case missingField(String)
    case invalidJSON
}

extension PropertyValueMap {
    static func from(_ json: [String: Any]) throws -> PropertyValueMap {
        var result: PropertyValueMap = [:]
        for (key, value) in json {
            result[key] = try PropertyValue.from(value)
        }
        return result
    }
}

extension PropertyValue {
    static func from(_ value: Any) throws -> PropertyValue {
        if value is NSNull {
            return .null
        }

        if let bool = value as? Bool {
            return .bool(bool)
        }

        if let number = value as? Double {
            return .number(number)
        }

        if let int = value as? Int {
            return .number(Double(int))
        }

        if let string = value as? String {
            return .string(string)
        }

        if let array = value as? [Any] {
            return .array(try array.map { try PropertyValue.from($0) })
        }

        if let dict = value as? [String: Any] {
            return try fromDictionary(dict)
        }

        throw PropertyValueError.unsupportedType
    }

    private static func fromDictionary(_ dict: [String: Any]) throws -> PropertyValue {
        // Check for discriminator fields
        if let type = dict["_type"] as? String,
           let id = dict["_id"] as? String {

            switch type {
            case "ComponentInstance":
                guard let componentName = dict["_component"] as? String else {
                    throw PropertyValueError.missingField("_component")
                }

                var arguments: [String: PropertyValue] = [:]
                for (key, value) in dict where !["_type", "_id", "_component"].contains(key) {
                    arguments[key] = try PropertyValue.from(value)
                }

                return .componentInstance(ComponentInstance(
                    id: id,
                    component: componentName,
                    arguments: arguments
                ))

            case "ContentReference":
                guard let contentId = dict["_content"] as? String else {
                    throw PropertyValueError.missingField("_content")
                }

                return .contentReference(ContentReference(
                    id: id,
                    content: contentId
                ))

            default:
                // Unknown _type, treat as object
                return try .object(PropertyValueMap.from(dict))
            }
        }

        // Check for MediaAsset structure
        if let id = dict["id"] as? String,
           let mimeType = dict["mimeType"] as? String,
           let url = dict["url"] as? String,
           let size = dict["size"] as? Int {

            var dimensions: MediaDimensions?
            if let dimensionsDict = dict["dimensions"] as? [String: Any],
               let width = dimensionsDict["width"] as? Int,
               let height = dimensionsDict["height"] as? Int {
                dimensions = MediaDimensions(width: width, height: height)
            }

            return .asset(MediaAsset(
                id: id,
                mimeType: mimeType,
                size: size,
                url: url,
                dimensions: dimensions
            ))
        }

        // Regular object
        return try .object(PropertyValueMap.from(dict))
    }
}
