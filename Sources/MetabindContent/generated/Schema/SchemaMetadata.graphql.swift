// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == MetabindContent.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == MetabindContent.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == MetabindContent.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == MetabindContent.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "Asset": return MetabindContent.Objects.Asset
    case "AssetList": return MetabindContent.Objects.AssetList
    case "Component": return MetabindContent.Objects.Component
    case "ComponentList": return MetabindContent.Objects.ComponentList
    case "Content": return MetabindContent.Objects.Content
    case "ContentList": return MetabindContent.Objects.ContentList
    case "ContentType": return MetabindContent.Objects.ContentType
    case "ContentTypeList": return MetabindContent.Objects.ContentTypeList
    case "ContentUpdate": return MetabindContent.Objects.ContentUpdate
    case "CursorPagination": return MetabindContent.Objects.CursorPagination
    case "Package": return MetabindContent.Objects.Package
    case "PackageDependency": return MetabindContent.Objects.PackageDependency
    case "PackageList": return MetabindContent.Objects.PackageList
    case "Query": return MetabindContent.Objects.Query
    case "ResolvedPackageData": return MetabindContent.Objects.ResolvedPackageData
    case "ResolvedPackageRef": return MetabindContent.Objects.ResolvedPackageRef
    case "SavedSearch": return MetabindContent.Objects.SavedSearch
    case "SavedSearchList": return MetabindContent.Objects.SavedSearchList
    case "Subscription": return MetabindContent.Objects.Subscription
    case "Tag": return MetabindContent.Objects.Tag
    case "TagList": return MetabindContent.Objects.TagList
    default: return nil
    }
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
